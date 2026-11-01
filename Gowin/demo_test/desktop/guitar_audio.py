"""预计算拨弦波形、复音混合与电脑默认输出；无触发时仅输出零样本。"""
from array import array
import math
import queue
import random
import threading
import time
from guitar_core import FREQUENCIES


def plucked_string(frequency, rate, duration=2.0, seed=0):
    length = max(2, round(rate/frequency+.5))
    rng = random.Random(seed)
    delay = [rng.uniform(-1, 1) for _ in range(length)]
    mean = sum(delay)/length
    delay = [v-mean for v in delay]
    result = array('h')
    total = round(rate*duration)
    attack, release = max(1, round(rate*.002)), max(1, round(rate*.07))
    # 平均低通形成拨弦的高频衰减；随音高补偿每次往返的损耗。
    damping = math.exp(-2.0/(frequency*duration))
    for n in range(total):
        i = n % length
        value = delay[i]
        delay[i] = damping*.5*(value+delay[(i+1) % length])
        envelope = min(1, n/attack, (total-1-n)/release)
        result.append(round(max(-1, min(1, value))*9500*envelope))
    return result


class GuitarMixer:
    def __init__(self, samples, rate):
        self.samples, self.rate = samples, rate
        self.voices = []
        self.volume = .30

    def pluck(self, string, delay=0):
        # 每根弦保留当前拨弦的尾音；全局限制24声部避免快速扫弦无限累积。
        self.voices = self.voices[-23:]
        self.voices.append([string, -round(delay*self.rate)])

    def silence(self):
        self.voices.clear()

    def render(self, frames, channels=2):
        mixed = [0]*frames
        remaining = []
        for string, position in self.voices:
            sample = self.samples[string]
            start = max(0, -position)
            end = min(frames, len(sample)-position)
            for i in range(start, end):
                mixed[i] += sample[position+i]
            position += frames
            if position < len(sample):
                remaining.append([string, position])
        self.voices = remaining
        pcm = array('h')
        for value in mixed:
            value = max(-32767, min(32767, round(value*self.volume)))
            pcm.extend([value]*channels)
        return pcm.tobytes()


class GuitarAudio:
    def __init__(self):
        self.commands = queue.Queue(maxsize=64)
        self.thread = None
        self.stop_event = threading.Event()
        self.panic_event = threading.Event()
        self.volume = .30
        self.status = '等待实时触摸板'
        self.ready = False
        self.error = ''
        self.rate = self.channels = 0
        self.device = ''
        self.underflows = self.plucks = self.dropped = self.blocks = self.nonzero_blocks = 0
        self.generation = 0

    def start(self):
        if self.thread is not None:
            return
        self.status = '正在准备电脑音频…'
        self.thread = threading.Thread(target=self.run, daemon=True, name='guitar-audio')
        self.thread.start()

    def pluck(self, event):
        if not self.ready:
            return False
        try:
            self.commands.put_nowait((self.generation, time.monotonic(), event.string, event.delay))
            return True
        except queue.Full:
            self.dropped += 1
            return False

    def silence(self):
        self.generation += 1
        self.panic_event.set()

    def run(self):
        try:
            import sounddevice as sd
            host = next((h for h in sd.query_hostapis() if h['name']=='Windows WASAPI' and h['default_output_device']>=0), None)
            device_index = host['default_output_device'] if host else sd.default.device[1]
            info = sd.query_devices(device_index, 'output')
            self.device = info['name']
            self.rate = round(info['default_samplerate'])
            self.channels = min(2, info['max_output_channels'])
            samples = [plucked_string(f, self.rate, seed=i+1) for i, f in enumerate(FREQUENCIES)]
            mixer = GuitarMixer(samples, self.rate)

            def callback(outdata, frames, timing, status):
                try:
                    if status.output_underflow:
                        self.underflows += 1
                    if self.panic_event.is_set():
                        mixer.silence()
                        self.panic_event.clear()
                    while True:
                        try:
                            generation, created, string, delay = self.commands.get_nowait()
                        except queue.Empty:
                            break
                        if generation == self.generation and time.monotonic()-created <= .2:
                            mixer.pluck(string, delay)
                            self.plucks += 1
                        else:
                            self.dropped += 1
                    mixer.volume = self.volume
                    pcm = mixer.render(frames, self.channels)
                    outdata[:] = pcm
                    self.blocks += 1
                    if any(pcm):
                        self.nonzero_blocks += 1
                except Exception as exc:
                    outdata[:] = bytes(len(outdata))
                    self.error = str(exc)
                    self.ready = False
                    raise sd.CallbackAbort

            extra = sd.WasapiSettings(auto_convert=True) if host else None
            with sd.RawOutputStream(device=device_index, samplerate=self.rate, channels=self.channels,
                                    dtype='int16', blocksize=256, latency='low', extra_settings=extra,
                                    callback=callback) as stream:
                self.ready = True
                self.status = '电脑音频就绪'
                while not self.stop_event.wait(.1):
                    if not stream.active:
                        raise RuntimeError(self.error or '音频输出流已停止')
        except Exception as exc:
            self.error = str(exc)
            self.status = '音频不可用：'+str(exc)
        finally:
            self.ready = False

    def close(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=3)

    def snapshot(self):
        return dict(ready=self.ready, status=self.status, error=self.error, device=self.device,
                    sample_rate=self.rate, channels=self.channels, volume=self.volume,
                    plucks=self.plucks, underflows=self.underflows, dropped=self.dropped,
                    blocks=self.blocks, nonzero_blocks=self.nonzero_blocks)
