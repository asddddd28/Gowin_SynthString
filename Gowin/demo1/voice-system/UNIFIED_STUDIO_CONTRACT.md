# Unified Studio hardware contract

The UI uses protocol 5 exclusively for sounding notes and patches. The existing
offline asset parser is retained for factory basic presets, wavetable files and
Surge OSC. Four distinct patches may be assigned across 32 physical keys; eight
voices share the unchanged six-operator DSP pool at 50 MHz. The application must
not silently evict a patch assigned to another key. A shared-patch edit and a
whole-keyboard assignment are explicit choices.

## Board-local protocol extension

The 52-byte request and 32-byte CRC-protected response stay unchanged. Kind 3
addresses board-local facilities; it uses the same durable sequence/replay rules.
All unused payload words must be zero. No local transaction enters the DSP AXI
queue. A local rejection is returned in response status, with no side effect.

| Opcode | Argument | Payload / result |
|---|---|---|
| 0 | 0 | capabilities: magic 0x53544d31, version 1, 50000000 Hz, 1024 cycles |
| 1 | key 0..31 | write phase word, descriptor (slot bits 1:0, MIDI note 8:2, velocity 15:9) |
| 2 | 0 | start a frozen 512-sample signed16 left-output PCM snapshot; reject while capturing |
| 3 | 0 | last latency cycles, maximum cycles, observation count, capture generation/status/key |
| 4 | key 0..31 | read phase and descriptor from the actual key table |
| 5 | chunk 0..63 | read eight consecutive signed16 samples; reject until the capture is ready |

Keyboard mapping is synchronous RAM with initialized MIDI 48..79, velocity 100,
patch 0. Writes acknowledge after RAM write. A concurrently prepared key event
retains its latched mapping; release uses its original identity. A later rising
edge uses the new mapping. App changes persist only after board acknowledgment.

## Monitoring semantics

PCM is sampled at the PT8211 frame acceptance boundary, after signed16 rounding
and saturation. The capture is frozen until another capture command; serial reads
never stop audio. 115200 baud limits visualization refresh to approximately 1 Hz,
which is shown explicitly along with freshness. It is a hardware snapshot, not
a synthesis preview or an acoustic recording. FFT uses a Hann window on 512 real
samples at 48828.125 Hz (95.367 Hz bin spacing).

Latency starts when the key source prepares a Note-On and ends when the first
PCM frame containing that accepted event reaches the digital DAC frame boundary.
Note-On completion returns the first affected frame tag in bits 63:32. A single
observation is in flight; simultaneous events are coalesced for monitoring only,
never for synthesis. Failed events cancel the observation. This excludes ADC
scan/debounce, analog DAC/headphone delay, and audible envelope attack.

Validation: distinct physical key mappings; held-key release after remapping;
duplicate requests have one side effect; malformed local packets rejected;
capture frozen/read ordering; actual PCM quantization; tagged latency across
queued pre-event frames; old protocol regression; 50 MHz synthesis/route before
SRAM programming. The DSP datapath, FX-disabled choice and sample rate stay fixed.
