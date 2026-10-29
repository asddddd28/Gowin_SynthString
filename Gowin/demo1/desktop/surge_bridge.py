"""Surge XT 本机 OSC 读取与显式包络映射；不发送音符或写入软件参数。"""
import copy
import datetime
import math
import queue
import socket
import struct
import threading

from profiles import validate_profile

SNAPSHOT_FORMAT = 'tang-surge-snapshot-v1'


def osc_string(value):
    """OSC UTF-8 字符串按四字节补零。"""
    if '\0' in value:
        raise ValueError('OSC 字符串不能含有空字符。')
    raw = value.encode('utf-8') + b'\0'
    return raw + b'\0' * (-len(raw) % 4)


def query_message(address):
    """查询不带参数，避免把读取变为写入。"""
    if not address.startswith('/q/'):
        raise ValueError('桥接只允许读取查询。')
    return osc_string(address) + osc_string(',')


def decode_packet(raw, depth=0):
    """有界解析 OSC 消息及嵌套 bundle；所有多字节值均为网络字节序。"""
    if not isinstance(raw, bytes) or not raw or len(raw) > 65507 or depth > 8:
        raise ValueError('OSC 数据包长度或嵌套深度不合法。')
    if raw.startswith(b'#bundle\0'):
        if len(raw) < 16:
            raise ValueError('OSC bundle 缺少时间标记。')
        position = 16
        messages = []
        while position < len(raw):
            if position + 4 > len(raw):
                raise ValueError('OSC bundle 长度字段被截断。')
            size = struct.unpack_from('>i', raw, position)[0]
            position += 4
            if size <= 0 or position + size > len(raw):
                raise ValueError('OSC bundle 子包越界。')
            messages.extend(decode_packet(raw[position:position + size], depth + 1))
            position += size
            if len(messages) > 1024:
                raise ValueError('OSC bundle 消息过多。')
        return messages

    def read_string(position):
        end = raw.find(b'\0', position)
        if end < 0:
            raise ValueError('OSC 字符串缺少结束符。')
        next_position = (end + 4) & ~3
        if next_position > len(raw) or any(raw[end:next_position]):
            raise ValueError('OSC 字符串填充不合法。')
        return raw[position:end].decode('utf-8'), next_position

    try:
        address, position = read_string(0)
        tags, position = read_string(position)
        if not address.startswith('/') or len(address) > 256 or not tags.startswith(',') or len(tags) > 33:
            raise ValueError('OSC 地址或类型标记不合法。')
        values = []
        for tag in tags[1:]:
            if tag == 's':
                value, position = read_string(position)
            elif tag in ('f', 'i'):
                if position + 4 > len(raw):
                    raise ValueError('OSC 数值被截断。')
                value = struct.unpack_from('>' + tag, raw, position)[0]
                position += 4
                if isinstance(value, float) and not math.isfinite(value):
                    raise ValueError('OSC 数值不是有限数。')
            elif tag in ('T', 'F'):
                value = tag == 'T'
            else:
                raise ValueError('暂不支持的 OSC 类型：' + tag)
            values.append(value)
        if position != len(raw):
            raise ValueError('OSC 消息包含未声明的尾部。')
        return [(address, values)]
    except (UnicodeDecodeError, struct.error) as error:
        raise ValueError('OSC 编码错误。') from error


class OscReader:
    """只绑定回环接口；后台线程只接收数据，不操作 Tk 控件。"""
    def __init__(self, input_port=53280, output_port=53281):
        if any(type(port) is not int or not 1024 <= port <= 65535 for port in (input_port, output_port)) or input_port == output_port:
            raise ValueError('两个 OSC 端口须不同，范围 1024..65535。')
        self.input_port = input_port
        self.events = queue.Queue(maxsize=8192)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.socket.bind(('127.0.0.1', output_port))
            self.socket.settimeout(0.1)
        except OSError:
            self.socket.close()
            raise
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()
        self.query()

    def query(self):
        self.socket.sendto(query_message('/q/all_params'), ('127.0.0.1', self.input_port))

    def close(self):
        self.stop.set()
        self.socket.close()
        if self.thread.is_alive():
            self.thread.join(timeout=0.4)

    def run(self):
        while not self.stop.is_set():
            try:
                raw, peer = self.socket.recvfrom(65507)
                if peer[0] != '127.0.0.1':
                    continue
                messages = decode_packet(raw)
                self.events.put_nowait(('messages', messages))
            except socket.timeout:
                continue
            except ValueError:
                # 不可信 UDP 数据不能终止后续正常接收。
                continue
            except queue.Full:
                self.stop.set()
                # 队列溢出后禁止使用可能丢字段的快照。
                while not self.events.empty():
                    try:
                        self.events.get_nowait()
                    except queue.Empty:
                        break
                self.events.put_nowait(('error', 'OSC 消息过多，请停止快速操作并重新连接。'))
            except OSError as error:
                if not self.stop.is_set():
                    try:
                        self.events.put_nowait(('error', str(error)))
                    except queue.Full:
                        pass
                self.stop.set()


class SurgeSnapshot:
    """保存软件参数及其范围文档；载入新音色时清除旧快照。"""
    def __init__(self):
        self.parameters = {}
        self.docs = {}
        self.patch = ''

    def feed(self, address, values):
        if address in ('/patch/load', '/patch'):
            self.parameters.clear()
            self.docs.clear()
            self.patch = str(values[0]) if values else ''
            return True
        if address.startswith('/param/') and values and type(values[0]) in (int, float) and math.isfinite(values[0]):
            if len(self.parameters) >= 4096 and address not in self.parameters:
                raise ValueError('参数数量超过限制。')
            self.parameters[address] = dict(value=values[0], display=str(values[1]) if len(values) > 1 else '')
        elif address.startswith('/doc/param/') and not address.endswith('/ext') and len(values) == 4:
            if len(self.docs) >= 4096 and address[4:] not in self.docs:
                raise ValueError('参数文档数量超过限制。')
            self.docs[address[4:]] = dict(name=str(values[0]), type=str(values[1]), minimum=str(values[2]), maximum=str(values[3]))
        return False

    def export(self):
        return dict(format=SNAPSHOT_FORMAT, captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    patch=self.patch, parameters=copy.deepcopy(self.parameters), docs=copy.deepcopy(self.docs))

    @classmethod
    def from_json(cls, data):
        if not isinstance(data, dict) or data.get('format') != SNAPSHOT_FORMAT:
            raise ValueError('请选择 Surge OSC 快照 JSON。')
        result = cls()
        result.patch = str(data.get('patch', ''))[:1024]
        for key in ('parameters', 'docs'):
            items = data.get(key)
            if not isinstance(items, dict) or len(items) > 4096:
                raise ValueError('快照字段或数量不合法。')
            for address, item in items.items():
                if not isinstance(address, str) or not address.startswith('/param/') or len(address) > 256 or not isinstance(item, dict):
                    raise ValueError('快照参数地址不合法。')
                if key == 'parameters':
                    value = item.get('value')
                    if type(value) not in (int, float) or not math.isfinite(value):
                        raise ValueError('快照参数必须为有限数。')
                    result.feed(address, [value, str(item.get('display', ''))[:1024]])
                else:
                    result.feed('/doc' + address, [item.get(n, '') for n in ('name', 'type', 'minimum', 'maximum')])
        return result


def map_envelope(snapshot, current_profile, scene='a'):
    """映射四个音量包络字段，保留振荡器及调制参数；不暗中截断时间。"""
    if scene not in ('a', 'b'):
        raise ValueError('请选择场景 A 或 B。')
    prefix = '/param/' + scene + '/aeg/'

    def value(field):
        address = prefix + field
        if address not in snapshot.parameters:
            raise ValueError('缺少 ' + address + '；请启用 Surge OSC 输入和输出后重新读取。')
        return snapshot.parameters[address]['value']

    def normalized(field, minimum, maximum):
        address = prefix + field
        doc = snapshot.docs.get(address, {})
        try:
            compatible = doc.get('type') == 'float' and float(doc['minimum']) == minimum and float(doc['maximum']) == maximum
        except (KeyError, ValueError, TypeError):
            compatible = False
        if not compatible:
            raise ValueError('缺少或不兼容的参数范围文档：' + address)
        result = value(field)
        if not 0 <= result <= 1:
            raise ValueError('参数超出归一化范围：' + address)
        return result

    result = copy.deepcopy(validate_profile(current_profile))
    for field in ('attack', 'decay', 'release'):
        tempo_sync = value(field + '/tempo_sync+')
        if tempo_sync not in (0, 1) or tempo_sync:
            raise ValueError(field + ' 使用节拍同步，尚未实现按 BPM 换算；请先关闭该段节拍同步。')
        native = normalized(field, -8, 5) * 13 - 8
        milliseconds = 0.0 if field == 'attack' and native < -7.99 else (2 ** native) * 1000
        if milliseconds > 5000:
            raise ValueError(field + ' 超过硬件界面的 5000 ms 上限；请缩短后重新读取。')
        result[field] = milliseconds
    result['sustain'] = normalized('sustain', 0, 1) * 100
    if value('release/deform+') != 0:
        raise ValueError('释放段启用了 Freeze 或形变选项，当前硬件不能表达。')
    validate_profile(result)
    notes = ['只映射 A/D/S/R；振荡器、FM/AM 与调制包络保持当前硬件设置。',
             'FPGA 使用线性包络及峰值参考释放；Surge 的曲线、模拟模式及提前松键时长可能不同。',
             '滤波、效果器、调制矩阵、第三振荡器和场景组合尚未移植；这不是完整音色转换。']
    return result, notes
