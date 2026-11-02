# FM1/DX7 four-preset compatibility increment

The source library is pinned in `assets/fm1/SOURCE.json`. Preserve all 128 raw
voices; initially qualify PIANO 2 (A05), ORGAN 1 (A02), BASS 3 (B11), BRASS 2
(C05). Four double-buffered resident slots remain independent of library IDs.
No FPGA reprogramming is part of this increment. The existing candidate has no
successful routed 50 MHz timing result.

Before RTL: immutable backup `reports/fm1-before/sources.zip`; explicit contracts,
WaveDrom and an independent numerical model. Add DX logarithmic EG, rate/key/
velocity scaling, output-level mapping, DX PM/feedback scaling and a ratio range
of 64. Native six-row programs retain their numerical behavior.

ABI increment: core flags bit15 selects DX mode, bits22:16 scaled output level.
Core shape packs breakpoint[6:0], left depth[13:7], right depth[20:14], left
curve[22:21], right curve[24:23], rate scaling[27:25], velocity sensitivity[30:28].
DX envelope words are four pre-scaled levels (0..4032) and four rates (0..63).
The release target must be zero for this first profile. DX feedback word is0..7;
depth is0. Only sine/PM is legal in DX mode. Native mode retains old encoding.
NoteOn/Update word4 optionally carries marker bit31, velocity[13:7], note[6:0].
Zero retains the legacy defaults of note60 and velocity100. Duplicate NoteIDs
must compare this metadata too. New-host compatibility checks prevent sending
the extension to an older engine.
Live A3 commits that change any row between native and DX EG format return BUSY10
while voices use that patch. The draft remains intact; release/panic followed by
a new-sequence commit is safe. Same-format live parameter commits remain allowed.

AxisDxEnvelope request = ten existing EG words, metadata word, scaling word
(384 bits); result = log level, stage/status, amplitude (96 bits). Metadata:
note[6:0], velocity[13:7], scaled output level[20:14]. E0 accepts, E1 decodes
stage/scaling, E2 computes key scaling/rate, E3 target, E4 advances and reads
exp2 ROM, E5 publishes. Output remains stable until accepted. It runs beside
wave generation and must not increase the existing operator's ten-cycle result
latency or 1024-cycle system deadline.

This is a bounded compatibility profile, not bit-identical DX7/FM1 emulation:
continuous sample-rate-adjusted EG instead of original control-block stepping,
256-entry exponential LUT, existing interpolated sine, fixed polyphony headroom.
Pitch EG, active DX LFO/AMS, multi-operator feedback (alg4/6), nonzero release
level, free-running oscillator mode and transpose are explicitly blocked in the
first import profile. Invalid original values are reported, not silently clamped.

Validation: strict SysEx framing/checksum and VCED/VMEM round trip; factory hash;
all algorithm DAGs; four actual patch programs; DX arithmetic vectors, stalls,
reset cancellation; mixed native/DX voices and all resident slots; repeated
NoteOn metadata conflicts; system UART/keyboard/AXI/PCM and native regression.
Publish exact test coverage, style-gate findings and remaining hardware limits.
