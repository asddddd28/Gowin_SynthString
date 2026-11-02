# tb_tactile_buttons

Self-checking bench for six `TactileInput` instances and `TactileReport` with the
real `EncoderUartTx`. Inputs use an accelerated five-cycle stability window;
the production value is 250000 cycles at 50 MHz. The top-level startup counter
and pin constraints are checked by implementation and hardware, not this bench.

Checks: rejection of press/release bounce, each channel separately, simultaneous
press/release, long hold without repeat, modulo press-count wrap, and reset while
held. Raw-edge counts remain observable independently of debounced counters.

UART is sampled at bit centers from the actual serial TX output. Three frames
are written to `sim/uart.bin`. The Python reference decoder checks CRC and every
field. Rust integration tests replay the same file at every split size. Inputs
change after the first snapshot: frame zero retains the old masks, following
frames carry the new masks. A simulation timeout or assertion is fatal.

```wavedrom
{ "signal": [
  { "name": "capture", "wave": "010....." },
  { "name": "input_masks", "wave": "=..=....", "data": ["15 / 0A", "3F / 3F"] },
  { "name": "frame_payload", "wave": "x=......", "data": ["15 / 0A snapshot"] },
  { "name": "uart", "wave": "1x......" }
] }
```

This diagram is conceptual, not a measured serial waveform.
