# FM1 board and App validation

Authorized: rebuild, download a tested SRAM image to the connected Tang Mega60K,
update the Rust/Tauri App and test the real command/audio chain. Keep the existing
working bitstream and executable in `reports/pre-board-fm1/backup.zip`.

Existing static review and synthesis identify an eight-entry chained64-bit age
comparison on the critical control path (estimated13.564MHz). Replace only this
CAM search with an interruptible eight-cycle lookup. The held input command is
not accepted until lookup completes. Every sample tick aborts lookup and has
priority; the search restarts after audio rendering, so no stale result crosses
a frame boundary. Exact NoteID, first free slot, oldest age and tie ordering stay
unchanged. Audio sample count and operator arithmetic do not change.

Classifications: modify and validate. Public gates: compile, ast, readability,
comment, naming, profile, testbench, toolchain. Existing style debt is reported
separately; this user's explicit board-test instruction authorizes an experimental
SRAM test, not a claim of zero-warning production delivery. Require real bitstream
generation and inspect routed timing; do not manufacture constraints or claim a
synthesis estimate as final timing. Do not alter Flash/SD contents.

Before RTL edits: independent lookup model and specification/WaveDrom. Validate
duplicate notes, replay, stealing, release, command stalls and sample-tick
preemption; run full mixed native/DX regression and top-level UART/ADC/PCM tests.

App: dedicated protocol5 session in Rust, same52-byte request/32-byte response,
CRC16, stop-and-wait, retry identity, persistent pending transaction and explicit
new-session action after reset. Read-only ABI preflight before patch commands.
Four preset slots, 128-entry read-only library with unsupported status, note/chord
performance and velocity, volume/pan/sustain, FX controls and live telemetry.
Provide a compiled executable and use the actual COM port for hardware checks.

Timing follow-up: UART packet comparison uses registered 16-bit equality chunks.
Voice commands now predecode signature/payload chunks, independently classify
identity and business validity, then register the selected completion. A sample
tick cancels every stage. FX uses the same chunked predecode with audio priority.
This removes inferred 328/336-bit carry chains. The resulting synthesis estimate
is 52.112 MHz; only the final routed report can qualify the 50 MHz board image.

UI packaging: `app/SynthStringVoiceStudio.exe` includes embedded frontend resources,
six-operator raw DX editing, volume/velocity knobs, MIDI/PC/pointer performance,
four resident slots, shared FX and hardware counters. Whole-page vertical scrolling
and a visible scrollbar were added following the user's testing feedback.
Computer Use was stopped by physical Escape; no further window automation follows.

Routed-timing follow-up: multiplier sharing reduced DSP118 to92 and physical
BSRAM112 to94; that candidate routed at47.549MHz and was not programmed.
A registered424-bit command head and four-stage route pipeline now break the
reported control and modulation paths. Eight routes complete in13 rather than17
clocks; full voice866 + FX72 + interfaces2 =940/1024. Force the four-entry command
storage to registers to avoid wide-shallow BSRAM inference. Final board evidence
is recorded in BOARD_TEST.md; historical estimates above are not acceptance data.
