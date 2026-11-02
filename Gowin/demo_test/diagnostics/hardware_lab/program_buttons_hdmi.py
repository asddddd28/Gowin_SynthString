"""SRAM-only validated HDMI hub download and read-only raw serial capture."""
from pathlib import Path
import hashlib
import json
import subprocess
import time
import serial
from serial.tools import list_ports

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'reports/buttons_merge'
PROGRAMMER = 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'
preflight = json.loads((OUT / 'preflight.json').read_text(encoding='utf-8'))
build = preflight['hardware_hdmi']
assert preflight['simulation_passed'] and build['timing_clean']
assert hashlib.sha256(Path(build['bitstream']).read_bytes()).hexdigest() == build['bitstream_sha256']
for source, digest in build['source_sha256'].items():
    assert hashlib.sha256(Path(source).read_bytes()).hexdigest() == digest, source
ports = [p for p in list_ports.comports() if p.device == 'COM4']
assert len(ports) == 1 and (ports[0].vid, ports[0].pid, ports[0].serial_number) == (0x0403, 0x6010, '2025030317B')
port = serial.Serial(port=None, baudrate=115200, timeout=.03, write_timeout=.5)
port.dtr = False
port.rts = False
port.port = 'COM4'
port.open()  # Abort before programming if another App owns UART.
try:
    with (OUT / 'program_sram.log').open('w', encoding='utf-8') as log:
        process = subprocess.run([PROGRAMMER, '--device', 'GW5AT-60B', '--cable-index', '4',
            '--run', '2', '--frequency', '15MHz', '--fsFile', build['bitstream']],
            stdout=log, stderr=subprocess.STDOUT, timeout=90)
    log = (OUT / 'program_sram.log').read_text(encoding='utf-8')
    assert process.returncode == 0 and 'Finished.' in log, log[-1000:]
    print(log[-500:], flush=True)
    until = time.monotonic() + 1
    while time.monotonic() < until:
        port.read(max(1, min(4096, port.in_waiting)))
    port.reset_input_buffer()
    captured = bytearray()
    until = time.monotonic() + 8
    while time.monotonic() < until:
        captured.extend(port.read(max(1, min(4096, port.in_waiting))))
finally:
    port.close()
(OUT / 'live_uart.bin').write_bytes(captured)
assert b'H100FF0101*9B\r\n' in captured and b'B1' in captured, 'No valid new identity / six-switch stream'
with (OUT / 'codes_after.log').open('w', encoding='utf-8') as log:
    process = subprocess.run([PROGRAMMER, '--device', 'GW5AT-60B', '--cable-index', '4', '--run', '0'],
        stdout=log, stderr=subprocess.STDOUT, timeout=20)
assert process.returncode == 0
print((OUT / 'codes_after.log').read_text(encoding='utf-8')[-350:])
print(f'Raw capture: {len(captured)} bytes. UART closed. No FPGA flash or bridge configuration written.')
