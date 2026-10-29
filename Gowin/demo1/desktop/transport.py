"""后台串口线程；主线程仅操作队列，不阻塞 Tk 窗口。"""
import queue
import threading
import time
from collections import deque
import serial
from protocol import packet, StatusParser
from wavetable import TableTransfer, PairTransfer
from profiles import ProfileTransfer
from pcm import PcmTransfer


class SerialLink:
    def __init__(self, port, factory=None):
        self.port = port
        self.factory = factory or serial.Serial
        self.events = queue.Queue()
        self.pending = deque()
        self.transfer = None
        self.upload_request = None
        self.pcm_request = None
        self.profile_request = None
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def send(self, frames):
        with self.lock:
            if self.stop.is_set():
                return False
            if len(self.pending) + len(frames) > 256:
                self.pending.clear()
                self.pending.append(packet(4))
                self.events.put(('overflow', '发送队列已清空并请求停止，请重新按键。'))
                return False
            self.pending.extend(frames)
        return True

    def upload(self, samples):
        from wavetable import validate_samples
        samples = tuple(validate_samples(list(samples)))
        with self.lock:
            if self.stop.is_set() or self.transfer is not None or self.upload_request is not None or self.profile_request is not None or self.pcm_request is not None:
                return False
            self.upload_request = samples
        return True

    def upload_profiles(self, profiles):
        request=ProfileTransfer(profiles,time.monotonic())
        with self.lock:
            if self.stop.is_set() or self.transfer is not None or self.upload_request is not None or self.profile_request is not None or self.pcm_request is not None:
                return False
            self.profile_request=request
        return True

    def upload_pair(self, frames):
        request=PairTransfer(frames,time.monotonic())
        with self.lock:
            if self.stop.is_set() or self.transfer is not None or self.upload_request is not None or self.profile_request is not None or self.pcm_request is not None:
                return False
            self.pcm_request=request
        return True

    def upload_pcm(self, image):
        request=PcmTransfer(image,time.monotonic())
        with self.lock:
            if self.stop.is_set() or self.transfer is not None or self.upload_request is not None or self.profile_request is not None or self.pcm_request is not None:
                return False
            self.pcm_request=request
        return True

    def panic(self):
        with self.lock:
            self.pending.clear()
            self.pending.append(packet(4))

    def close(self):
        self.stop.set()
        self.thread.join(timeout=0.8)

    def run(self):
        device = None
        try:
            device = self.factory(port=None, baudrate=115200, timeout=0.01, write_timeout=0.2)
            device.port = self.port
            device.dtr = False
            device.rts = False
            device.open()
            device.reset_input_buffer()
            self.events.put(('open', self.port))
            parser = StatusParser()
            heartbeat = 0
            last_status = time.monotonic()
            while not self.stop.is_set():
                now = time.monotonic()
                # Polling is also the FPGA control-session heartbeat.
                if now >= heartbeat:
                    device.write(packet(5))
                    heartbeat = now + 0.5
                with self.lock:
                    frames = [self.pending.popleft() for _ in range(min(8, len(self.pending)))]
                with self.lock:
                    if self.upload_request is not None:
                        self.transfer=TableTransfer(self.upload_request,now)
                        self.upload_request=None
                    elif self.pcm_request is not None:
                        self.transfer=self.pcm_request;self.transfer.deadline=now+5
                        self.pcm_request=None
                    elif self.profile_request is not None:
                        self.transfer=self.profile_request;self.transfer.deadline=now+3
                        self.profile_request=None
                if self.transfer:
                    frames += self.transfer.advance(now)
                for frame in frames:
                    if device.write(frame) != len(frame):
                        raise OSError('串口写入不完整')
                for status in parser.feed(device.read(max(1, min(device.in_waiting, 512)))):
                    last_status = time.monotonic()
                    if status.get('table') or status.get('profile') or status.get('pcm'):
                        received_kind='pcm' if status.get('pcm') else 'profiles' if status.get('profile') else 'table'
                        if received_kind=='pcm':self.events.put(('pcm_status',status))
                        if self.transfer and (received_kind==getattr(self.transfer,'kind','table') or
                                (received_kind=='table' and getattr(self.transfer,'position_transfer',None) is not None)):
                            replies=self.transfer.advance(time.monotonic(),status)
                            for reply in replies:
                                if device.write(reply)!=len(reply):raise OSError('串口上传写入不完整')
                            prefix={'table':'upload','profiles':'profiles','pcm':'pcm'}[getattr(self.transfer,'kind','table')]
                            self.events.put((prefix+'_progress',self.transfer.count))
                    else:
                        self.events.put(('status', status))
                if self.transfer and (self.transfer.done or self.transfer.error):
                    prefix={'table':'upload','profiles':'profiles','pcm':'pcm'}[getattr(self.transfer,'kind','table')]
                    kind=prefix+('_done' if self.transfer.done else '_error')
                    self.events.put((kind,self.transfer.error or '上传校验完成'))
                    with self.lock:
                        self.transfer=None
                if now - last_status > 3:
                    raise OSError('3 秒内未收到有效 FPGA 状态包。请检查 COM 口、烧录文件和底板版本。')
        except (OSError, serial.SerialException, ValueError) as error:
            self.events.put(('error', str(error)))
        finally:
            self.stop.set()
            if device is not None:
                try:
                    if device.is_open:
                        device.write(packet(0x33))
                        device.write(packet(0x23))
                        device.write(packet(0x13))
                        device.write(packet(4))
                except (OSError, serial.SerialException):
                    pass
                device.close()
            self.events.put(('closed', None))
