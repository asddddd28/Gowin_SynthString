# 2-pin speaker test — 2026-11-02

The user attached one **4 ohm / 3 W dynamic speaker** and confirmed the 3.5 mm
headphone jack is unplugged. The local 31004 dock schematic (`reference/audio_page.png`)
shows J27 as the NS4263 left-channel bridge output and J28 as its right-channel
bridge output. Both pins of either connector are amplifier outputs; neither is
a separate ground connection. The exact occupied connector was not identified.

## Hardware and firmware

At entry, JTAG read ID 0x0001481B, User Code 0x00000000 and Status 0x36020239;
the FPGA was not running the previously tested HDMI or synthesizer configuration.
The existing audio firmware was verified against its simulation source hashes,
bitstream digest and current Gowin timing report, then downloaded to SRAM:

- Bitstream: `Gowin/demo1/keyboard-latency/impl/pnr/keyboard_latency.fs`
- SHA-256: `3a75079156d8297e54b693b39644fd1981deadba368cbdc0e5d5e6e1047d02ec`
- Download: Finished, User Code **0xFED2**, Status **0x76026238**.
- 50 MHz timing passes, reported fMax 50.134 MHz.
- PT8211 BCK=Y17, WS=AB17, DIN=AA16; amplifier enable PA_EN=AB16, active low.
- `LatencyAudioSystem` explicitly copies left PCM to right PCM, so the test
  reaches both speaker channels. There is no software choice of J27 versus J28.

No RTL, Flash, drivers or debugger firmware was changed. The existing
TangSynthStudio window was closed gracefully to release COM4 for testing.

## Short-tone tests

`test_speaker.py` temporarily sets K13 to a 440 Hz sine, velocity 80, attack
20 ms, sustain 0.7 and release 80 ms. Three short remote notes are played per
run. The script checks matching command ACKs, nonzero PCM, one active voice,
release back to zero, unchanged clipping counter, and valid telemetry.
It then stops all remote notes, sets volume to zero, restores K13's compiled
boot profile and closes the serial handle. It does not overwrite saved App banks.

| Master setting | Maximum observed PCM24 peak | Signed digital full-scale fraction | Telemetry | User hearing |
|---|---:|---:|---|---|
| 1 / 8 | 55,904 | 0.67% | 52 packets, 0 bad | No audible sound reported |
| 3 / 8 | 167,712 | 2.00% | 52 packets, 0 bad | “好像有声音，有点小” |
| 6 / 8 | 335,424 | 4.00% | 53 packets, 0 bad | Not separately confirmed |

These are **digital peak amplitudes**, not measured speaker voltage, acoustic
volume or delivered watts. The scale includes voice velocity, envelope and the
existing polyphonic mix normalization. The 6/8 test is approximately +6 dB in
digital amplitude relative to the 3/8 test, not a 6/8-of-3W power test.

The user's report establishes that the connected speaker produces a quiet
audible signal. It does not establish both physical output channels, absence of
distortion, or full-rated-power performance. The PC/JTAG/UART tools do not read
back the amplifier outputs or microphone audio; analog output power was not
measured. Last test ended with volume=0, active=0, gain=0, output_peak=0 and no
clip increment; the audio firmware remains loaded.

Evidence: `reports/program_sram.log`, `reports/preflight.json`, and the
`speaker_volume_{1,3,6}.json/.bin` captures. Run preflight without touching hardware:

```powershell
& 'D:/Projects/ai/Gowin/demo1/desktop/.venv/Scripts/python.exe' test_speaker.py --preflight-only
```

For another short audible run, with the App disconnected from COM4:

```powershell
& 'D:/Projects/ai/Gowin/demo1/desktop/.venv/Scripts/python.exe' test_speaker.py --volume 6
```
