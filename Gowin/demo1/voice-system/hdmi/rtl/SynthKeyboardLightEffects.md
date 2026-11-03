# SynthKeyboardLightEffects

Frame-snapshot LED renderer derived from demo_test `HardwareKeyLightEffects`.
Ports, per-key timers, newest-key interruption, 4×8 geometry, six palette
segments and all effect modes are unchanged. 50 MHz system clock, frame tick
from LedFrameTx. Pixel address is stable before the serializer loads GRB.

Exact arithmetic substitutions:
- Weight 32: identity; 16: divide by 2; 4: divide by 8.
- Weight 12: floor(3×channel/8), using an eight-bit shift/add, no multiplier.
- Radius floor(age/3) uses thresholds 3..36. Radii beyond this range never
  contribute because ripple/cross are disabled at age >=36.
- All palette channels remain 0..32. Output ordering is G, R, B.

Validation: 215 complete output frames / 6880 reference pixels in
`reports/keyboard-rgb/rgb-effects-opt.log`; the original demo_test is unmodified.
This derivative is used only by SynthKeyboardRgb.
