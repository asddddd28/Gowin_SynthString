"""Serial worker with a bounded ASCII FPGA-command queue; no debugger commands."""
import queue
import threading
import time
from pathlib import Path

import serial
from serial.tools import list_ports


def ports():
    found = list(list_ports.comports())
    found.sort(key=lambda p: (not (p.vid == 0x0403 and p.pid == 0x6010 and (p.serial_number or "").endswith("B")), p.device))
    return found


class Reader:
    def __init__(self, port=None, replay=None):
        self.port, self.replay = port, replay
        self.data = queue.Queue(maxsize=256)
        self.status = queue.Queue()
        self.outgoing = queue.Queue(maxsize=64)
        self.tx_bytes = 0
        self.stop_event = threading.Event()
        self.handle = None
        self.dropped = 0
        self.thread = threading.Thread(target=self.run, daemon=True, name="keyboard-input")

    def start(self):
        self.thread.start()

    def send(self, packet):
        if self.replay or self.stop_event.is_set() or not self.handle or not self.handle.is_open:
            raise ValueError('实时串口尚未打开')
        if not isinstance(packet, bytes) or len(packet) != 25 or packet[:1] != b'!' or packet[-1:] != b'\n':
            raise ValueError('仅允许固定格式FPGA命令')
        if any(c < 32 or c > 126 for c in packet[:-1]):
            raise ValueError('禁止发送调试器控制字符')
        self.outgoing.put_nowait(packet)

    def emit(self, data):
        try:
            self.data.put((time.monotonic(), data), timeout=.15)
        except queue.Full:
            self.dropped += len(data)

    def run(self):
        try:
            if self.replay:
                with Path(self.replay).open("rb") as handle:
                    self.status.put(("ready", "历史数据回放"))
                    while not self.stop_event.is_set():
                        data = handle.read(32 * 9)
                        if not data:
                            self.status.put(("eof", "回放结束"))
                            break
                        self.emit(data)
                        self.stop_event.wait(.0317)
            else:
                port = serial.Serial(port=None, baudrate=115200, bytesize=8, parity="N", stopbits=1,
                                     timeout=.02, write_timeout=.5, xonxoff=False, rtscts=False, dsrdtr=False)
                self.handle = port
                port.dtr = False
                port.rts = False
                port.port = self.port
                port.open()
                port.reset_input_buffer()
                self.status.put(("warmup", "正在排空调试器旧缓存…"))
                until = time.monotonic() + 2
                while time.monotonic() < until and not self.stop_event.is_set():
                    port.read(min(4096, max(1, port.in_waiting)))
                if self.stop_event.is_set():
                    return
                self.status.put(("ready", f"串口已打开 · {self.port}"))
                while not self.stop_event.is_set():
                    try:
                        packet = self.outgoing.get_nowait()
                    except queue.Empty:
                        packet = None
                    if packet is not None:
                        written = port.write(packet)
                        if written != len(packet):
                            raise serial.SerialTimeoutException('命令未完整发送')
                        self.tx_bytes += written
                    data = port.read(min(4096, max(1, port.in_waiting)))
                    if data:
                        self.emit(data)
        except Exception as exc:
            if not self.stop_event.is_set():
                self.status.put(("error", str(exc)))
        finally:
            if self.handle is not None:
                self.handle.close()
            self.status.put(("closed", "接口已释放"))

    def stop(self):
        self.stop_event.set()
        if self.handle is not None and self.handle.is_open:
            try:
                self.handle.cancel_read()
            except (AttributeError, serial.SerialException, OSError):
                pass
        if self.thread.is_alive():
            self.thread.join(timeout=.5)
