//! Native audio: serial events go straight to a bounded callback queue, never via the WebView.
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use crossbeam_channel::{bounded, Receiver, Sender};
use serde::Serialize;
use std::sync::{
    atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
    Arc, Mutex,
};

const FREQUENCIES: [f64; 6] = [82.4069, 110., 146.8324, 195.9977, 246.9417, 329.6276];
#[derive(Clone, Default, Serialize)]
pub struct AudioView {
    pub ready: bool,
    pub device: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub buffer_frames: u32,
    pub error: String,
    pub played: u64,
    pub dropped: u64,
}
#[derive(Clone, Copy)]
struct Pluck {
    string: usize,
    delay: f64,
    generation: u64,
}
pub struct Audio {
    enabled: Arc<AtomicBool>,
    volume: Arc<AtomicU32>,
    generation: Arc<AtomicU64>,
    tx: Sender<Pluck>,
    pub view: Arc<Mutex<AudioView>>,
}
fn waveform(f: f64, rate: u32, seed: u32) -> Vec<f32> {
    let len = (f64::from(rate) / f + 0.5).round() as usize;
    let mut rng = seed + 1;
    let mut delay: Vec<f32> = (0..len)
        .map(|_| {
            rng ^= rng << 13;
            rng ^= rng >> 17;
            rng ^= rng << 5;
            (rng as f64 / u32::MAX as f64 * 2. - 1.) as f32
        })
        .collect();
    let mean = delay.iter().sum::<f32>() / len as f32;
    for v in &mut delay {
        *v -= mean;
    }
    let total = rate as usize * 2;
    let damping = (-1. / f).exp() as f32;
    (0..total)
        .map(|i| {
            let index = i % len;
            let v = delay[index];
            delay[index] = damping * 0.5 * (v + delay[(index + 1) % len]);
            let env = (i as f32 / (rate as f32 * 0.002))
                .min((total - 1 - i) as f32 / (rate as f32 * 0.07))
                .min(1.);
            v * env * 0.29
        })
        .collect()
}
struct Mixer {
    samples: Vec<Vec<f32>>,
    voices: Vec<(usize, i64)>,
    rate: u32,
}
impl Mixer {
    fn new(rate: u32) -> Self {
        Self {
            samples: FREQUENCIES
                .iter()
                .enumerate()
                .map(|(i, f)| waveform(*f, rate, i as u32 + 701))
                .collect(),
            voices: Vec::with_capacity(24),
            rate,
        }
    }
    fn pluck(&mut self, p: Pluck) {
        if self.voices.len() == 24 {
            self.voices.remove(0);
        }
        self.voices
            .push((p.string, -(p.delay * f64::from(self.rate)).round() as i64));
    }
    fn sample(&mut self) -> f32 {
        let mut sum = 0.;
        for (string, pos) in &mut self.voices {
            if *pos >= 0 {
                if let Some(s) = self.samples[*string].get(*pos as usize) {
                    sum += s;
                }
            }
            *pos += 1;
        }
        self.voices
            .retain(|(s, p)| *p < (self.samples[*s].len() as i64));
        sum
    }
}
impl Audio {
    pub fn new() -> Arc<Self> {
        let (tx, rx) = bounded(64);
        let a = Arc::new(Self {
            enabled: Arc::new(AtomicBool::new(false)),
            volume: Arc::new(AtomicU32::new(0.3f32.to_bits())),
            generation: Arc::new(AtomicU64::new(0)),
            tx,
            view: Arc::new(Mutex::new(AudioView::default())),
        });
        let worker = a.clone();
        std::thread::Builder::new()
            .name("tang-audio".into())
            .spawn(move || {
                if let Err(e) = worker.run(rx) {
                    let mut v = worker.view.lock().unwrap();
                    v.ready = false;
                    v.error = e;
                }
            })
            .expect("audio thread");
        a
    }
    pub fn configure(&self, enabled: bool, volume: f32) {
        let old = self.enabled.swap(enabled, Ordering::AcqRel);
        self.volume
            .store(volume.clamp(0., 1.).to_bits(), Ordering::Release);
        if old && !enabled {
            self.panic();
        }
    }
    pub fn panic(&self) {
        self.generation.fetch_add(1, Ordering::AcqRel);
    }
    pub fn pluck(&self, string: usize, delay: f64) -> bool {
        if !self.enabled.load(Ordering::Acquire) || !self.view.lock().unwrap().ready {
            return false;
        }
        if self
            .tx
            .try_send(Pluck {
                string,
                delay,
                generation: self.generation.load(Ordering::Acquire),
            })
            .is_err()
        {
            self.view.lock().unwrap().dropped += 1;
            false
        } else {
            self.view.lock().unwrap().played += 1;
            true
        }
    }
    fn run(&self, rx: Receiver<Pluck>) -> Result<(), String> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or("没有可用的电脑音频输出")?;
        let supported = device.default_output_config().map_err(|e| e.to_string())?;
        let mut config: cpal::StreamConfig = supported.clone().into();
        let size = match supported.buffer_size() {
            cpal::SupportedBufferSize::Range { min, max } => 256u32.clamp(*min, *max),
            _ => 0,
        };
        if size > 0 {
            config.buffer_size = cpal::BufferSize::Fixed(size);
        }
        let format = supported.sample_format();
        let stream = match format {
            cpal::SampleFormat::F32 => self.stream::<f32>(&device, &config, rx.clone()),
            cpal::SampleFormat::I16 => self.stream::<i16>(&device, &config, rx.clone()),
            cpal::SampleFormat::U16 => self.stream::<u16>(&device, &config, rx.clone()),
            _ => Err("不支持此音频设备的采样格式".into()),
        };
        let (stream, actual_size) = match stream {
            Ok(s) => (s, size),
            Err(_) if size > 0 => {
                config.buffer_size = cpal::BufferSize::Default;
                let s = match format {
                    cpal::SampleFormat::F32 => self.stream::<f32>(&device, &config, rx),
                    cpal::SampleFormat::I16 => self.stream::<i16>(&device, &config, rx),
                    cpal::SampleFormat::U16 => self.stream::<u16>(&device, &config, rx),
                    _ => Err("不支持的采样格式".into()),
                }?;
                (s, 0)
            }
            Err(e) => return Err(e),
        };
        stream.play().map_err(|e| e.to_string())?;
        {
            let mut v = self.view.lock().unwrap();
            v.ready = true;
            v.device = device.name().unwrap_or("默认输出".into());
            v.sample_rate = config.sample_rate.0;
            v.channels = config.channels;
            v.buffer_frames = actual_size;
        }
        // The stream must live on this thread for the application's lifetime.
        loop {
            std::thread::park();
        }
    }
    fn stream<T>(
        &self,
        device: &cpal::Device,
        config: &cpal::StreamConfig,
        rx: Receiver<Pluck>,
    ) -> Result<cpal::Stream, String>
    where
        T: cpal::SizedSample + cpal::FromSample<f32>,
    {
        let mut mixer = Mixer::new(config.sample_rate.0);
        let channels = config.channels as usize;
        let enabled = self.enabled.clone();
        let volume = self.volume.clone();
        let generation = self.generation.clone();
        let mut seen = 0;
        let view = self.view.clone();
        device
            .build_output_stream(
                config,
                move |data: &mut [T], _| {
                    let epoch = generation.load(Ordering::Acquire);
                    let on = enabled.load(Ordering::Acquire);
                    if epoch != seen || !on {
                        mixer.voices.clear();
                        seen = epoch;
                    }
                    for _ in 0..64 {
                        match rx.try_recv() {
                            Ok(p) if on && p.generation == epoch => mixer.pluck(p),
                            Ok(_) => {}
                            Err(_) => break,
                        }
                    }
                    let gain = f32::from_bits(volume.load(Ordering::Acquire));
                    for frame in data.chunks_mut(channels) {
                        let sample = if on {
                            (mixer.sample() * gain).clamp(-1., 1.)
                        } else {
                            0.
                        };
                        for out in frame {
                            *out = T::from_sample(sample);
                        }
                    }
                },
                move |e| {
                    let mut v = view.lock().unwrap();
                    v.error = e.to_string();
                    v.ready = false;
                },
                None,
            )
            .map_err(|e| e.to_string())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn silence_pluck_and_polyphony() {
        let mut m = Mixer::new(48000);
        assert_eq!(m.sample(), 0.);
        for _ in 0..100 {
            m.pluck(Pluck {
                string: 0,
                delay: 0.,
                generation: 0,
            });
        }
        assert_eq!(m.voices.len(), 24);
        assert!((0..2000).any(|_| m.sample().abs() > 0.01));
        m.voices.clear();
        assert_eq!(m.sample(), 0.);
    }
    #[test]
    fn waveform_finite_and_fades() {
        let w = waveform(110., 48000, 1);
        assert_eq!(w.len(), 96000);
        assert!(w.iter().all(|v| v.is_finite()));
        assert_eq!(w[0], 0.);
        assert_eq!(w[w.len() - 1], 0.);
    }
}
