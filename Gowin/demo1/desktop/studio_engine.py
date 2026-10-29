"""Headless application controller for the Tauri UI; no Tk dependency.

All serial framing, resource validation and acknowledged transfers use the
existing desktop modules. This class is confined to the service's main thread.
"""
import copy
import json
import math
import os
from pathlib import Path
import queue
import time

from serial.tools import list_ports
from protocol import defaults, validate_config, packet, sound_packets, piano_sound
from profiles import validate_profile, from_sound, preset
from transport import SerialLink
from basic_bank import load_basic_bank
from wavetable import load_surge_frames, resample_frame, load_table, harmonic_piano_table
from wavetable_bank import encode_bank, MAX_BYTES
from wavetable_library import load_library, make_resource
from pcm import load_image
from surge_bridge import OscReader, SurgeSnapshot, map_envelope


def read_json(path):
    path = Path(path)
    if path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError('文件超过 2 MiB 限制。')
    return json.loads(path.read_text(encoding='utf-8-sig'))


class StudioEngine:
    def __init__(self, assets, config_path=None, link_factory=SerialLink):
        self.assets = Path(assets)
        self.config_path = Path(config_path) if config_path else (
            Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'TangSynth32/settings-tauri.json')
        self.link_factory = link_factory
        self.bank = load_basic_bank(self.assets / 'basic_bank')
        self.library = []
        self.config = validate_config(defaults())
        self.revision = 0
        self.message = '离线编辑已就绪。连接 DEBUG USB 后可同步音色。'
        self.level = 'info'
        source = self.config_path
        if not source.exists() and config_path is None:
            source = source.with_name('settings-pcm.json')
        if source.exists():
            try:
                self.config = self.validate_document(read_json(source))
                if source != self.config_path:
                    self.message = '已读取旧版配置；保存时写入独立的 Tauri 配置。'
            except (ValueError, TypeError, KeyError, OSError) as error:
                self.message = '配置未载入，使用默认值：' + str(error)
                self.level = 'error'
        self.link = None
        self.port = ''
        self.online = False
        self.synced = set()
        self.held = {}
        self.transfer = None
        self.progress = 0
        self.total = 0
        self.batch = []
        self.pending_resource = None
        self.active_resource = None
        self.pcm_available = False
        self.telemetry = None
        self.last_ui = time.monotonic()
        self.surge = None
        self.surge_snapshot = SurgeSnapshot()
        self.surge_message = '等待连接本机 Surge OSC。'
        demo = self.assets / 'wavetable_library/TSLIB.JSN'
        if demo.exists():
            self.library = load_library(demo)

    def tell(self, message, level='info'):
        self.message, self.level = message, level

    def validate_document(self, value):
        value = validate_config(copy.deepcopy(value))
        bindings = value.setdefault('tauri_bindings', {})
        if not isinstance(bindings, dict):
            raise ValueError('音色资源绑定格式无效。')
        for key, tid in bindings.items():
            if key not in {str(i) for i in range(32)} or type(tid) is not int:
                raise ValueError('资源绑定的音键或音色编号无效。')
            if not any(sound.timbre_id == tid and sound.samples is not None for sound in self.bank):
                raise ValueError('资源绑定未找到对应的基础波表音色。')
        return value

    def commit(self, candidate):
        candidate = self.validate_document(candidate)
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.config_path.with_suffix('.tmp')
        temporary.write_text(json.dumps(candidate, ensure_ascii=False, indent=2), encoding='utf-8')
        temporary.replace(self.config_path)
        self.config = candidate
        self.revision += 1

    @staticmethod
    def key_index(index):
        if type(index) is not int or not 0 <= index < 32:
            raise ValueError('音键编号必须为 0–31。')
        return index

    def idle(self, connected=False):
        if self.transfer:
            raise ValueError('请等待当前传输结束。')
        if connected and not self.online:
            raise ValueError('请先连接 FPGA，等待硬件响应。')

    def get_state(self):
        self.last_ui = time.monotonic()
        return dict(config=copy.deepcopy(self.config), revision=self.revision,
                    online=self.online, connecting=bool(self.link) and not self.online,
                    port=self.port, synced=sorted(self.synced), held=sorted(self.held),
                    transfer=self.transfer, progress=self.progress, total=self.total,
                    telemetry=self.telemetry, message=self.message, level=self.level,
                    pcm_available=self.pcm_available, active_resource=self.active_resource,
                    surge=dict(connected=bool(self.surge), patch=self.surge_snapshot.patch,
                               count=len(self.surge_snapshot.parameters), message=self.surge_message))

    def ports(self):
        return [dict(device=p.device, description=p.description) for p in list_ports.comports()]

    def connect(self, port):
        if self.link:
            raise ValueError('请先断开当前设备。')
        if not isinstance(port, str) or port not in [p.device for p in list_ports.comports()]:
            raise ValueError('请选择当前可用的串口。')
        self.port = port
        self.link = self.link_factory(port)
        self.link.start()
        self.tell('串口已打开，等待 FPGA 状态包…')

    def disconnect(self):
        if self.link:
            self.link.panic()
            self.link.close()
        self.link = None
        self.online = False
        self.port = ''
        self.held.clear()
        self.synced.clear()
        self.transfer = None
        self.pending_resource = None
        self.active_resource = None
        self.pcm_available = False
        self.telemetry = None
        self.tell('设备已断开。音色保留在电脑中。')

    def release_all(self):
        if self.online and self.held:
            self.link.send([packet(2, 32 + i) for i in self.held])
        self.held.clear()

    def panic(self):
        if self.link:
            self.link.panic()
        self.held.clear()
        self.preview_stop()
        self.tell('已请求紧急停止全部声部。' if self.online else '已停止电脑试听并清除按键。')

    def note_on(self, index, owner):
        index = self.key_index(index)
        if owner not in ('mouse', 'keyboard'):
            raise ValueError('无效演奏来源。')
        self.idle(connected=True)
        if index not in self.synced:
            raise ValueError('此音键尚未由硬件确认，请先同步。')
        item = self.config['keys'][index]
        p = item['synth']
        if p['mode'] == '采样钢琴' and not self.pcm_available:
            raise ValueError('请先上传 PCM 采样包。')
        if self.custom(p):
            bound = self.config.get('tauri_bindings', {}).get(str(index))
            if self.active_resource is None or (bound is not None and bound != self.active_resource):
                raise ValueError('此键的波表未驻留，请重新同步此键或上传波表。')
        owners = self.held.setdefault(index, set())
        if owner in owners:
            return
        if not owners and not self.link.send([packet(1, 32 + index, item['note'], item['velocity'])]):
            self.held.pop(index, None)
            raise ValueError('音符发送队列不可用。')
        owners.add(owner)
        self.last_ui = time.monotonic()

    def note_off(self, index, owner):
        index = self.key_index(index)
        owners = self.held.get(index)
        if owners:
            owners.discard(owner)
            if not owners:
                del self.held[index]
                if self.online:
                    self.link.send([packet(2, 32 + index)])

    @staticmethod
    def custom(profile):
        return '自定义波表' in (profile['wave_a'], profile['wave_b'])

    def save_key(self, index, key):
        self.idle()
        index = self.key_index(index)
        candidate = copy.deepcopy(self.config)
        candidate['keys'][index] = copy.deepcopy(key)
        if not self.custom(key['synth']):
            candidate.get('tauri_bindings', {}).pop(str(index), None)
        candidate = self.validate_document(candidate)
        self.release_all()
        self.commit(candidate)
        self.synced.discard(index)
        self.tell(f'音键 {index + 1:02} 已保存到电脑，尚未同步。')

    def bank_catalog(self):
        return [dict(id=s.timbre_id, title=s.title, category=s.category,
                     description=s.description, profile=s.profile, resource_id=s.resource_id,
                     waveform=list(s.samples[::8]) if s.samples else None) for s in self.bank]

    def bank_sound(self, timbre_id):
        sound = next((s for s in self.bank if s.timbre_id == timbre_id), None)
        if sound is None:
            raise ValueError('没有找到该音色。')
        return sound

    def load_preset(self, index, timbre_id):
        self.idle()
        index = self.key_index(index)
        sound = self.bank_sound(timbre_id)
        candidate = copy.deepcopy(self.config)
        candidate['keys'][index].update(name=sound.title[:24], synth=copy.deepcopy(sound.profile))
        bindings = candidate.setdefault('tauri_bindings', {})
        if sound.samples is not None:
            bindings[str(index)] = timbre_id
        else:
            bindings.pop(str(index), None)
        self.release_all()
        self.commit(candidate)
        self.synced.discard(index)
        self.tell(f'「{sound.title}」已载入音键 {index+1:02}，同步后可在硬件演奏。')

    def preview(self, timbre_id):
        import winsound
        sound = self.bank_sound(timbre_id)
        winsound.PlaySound(str(sound.preview), winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
        self.tell('电脑参考试听：' + sound.title + '（不是 FPGA 录音）。')

    def preview_stop(self):
        import winsound
        winsound.PlaySound(None, 0)

    def start_profiles(self, indices):
        self.release_all()
        batch = [(32 + i, dict(self.config['keys'][i]['synth'],
                              frame_position=self.config['keys'][i]['synth'].get('frame_position', 0))) for i in indices]
        if not self.link.upload_profiles(batch):
            raise ValueError('设备拒绝参数上传，请稍后重试。')
        self.batch = list(indices)
        self.synced.difference_update(indices)
        self.transfer, self.progress, self.total = 'profiles', 0, len(indices)
        self.tell('正在上传音键参数，等待硬件校验…')

    def sync(self, indices):
        self.idle(connected=True)
        if not isinstance(indices, list) or not indices or len(indices) > 32 or len(set(indices)) != len(indices):
            raise ValueError('请选择 1–32 个不同音键。')
        indices = [self.key_index(i) for i in indices]
        bindings = self.config.get('tauri_bindings', {})
        resources = {bindings[str(i)] for i in indices if str(i) in bindings and self.custom(self.config['keys'][i]['synth'])}
        if len(resources) > 1:
            raise ValueError('板上只有一对共享波表。多个不同波表音色请分别同步；换表会使旧波表音键待同步。')
        if resources:
            rid = next(iter(resources))
            if self.active_resource != rid:
                sound = self.bank_sound(rid)
                self.start_resource([list(sound.samples), list(sound.samples)], rid, indices)
                return
        self.start_profiles(indices)

    def start_resource(self, frames, resource, indices, candidate=None, single=False):
        self.idle(connected=True)
        self.release_all()
        accepted = self.link.upload(frames[0]) if single else self.link.upload_pair(frames)
        if not accepted:
            raise ValueError('设备拒绝波表上传，请稍后重试。')
        self.pending_resource = dict(resource=resource, indices=list(indices), candidate=candidate)
        self.transfer, self.progress, self.total = 'wavetable', 0, 1024 if single else 2048
        self.tell('正在传输波表；等待资源提交后再同步音键参数。')

    def library_catalog(self):
        return [dict(id=i, title=r.title, frames=r.frame_count, resource_id=r.resource_id,
                     revision=r.revision) for i, r in enumerate(self.library)]

    def load_library_file(self, path):
        path = Path(path)
        if path.suffix.lower() == '.jsn' or path.name.upper() == 'TSINDEX.BIN':
            resources = load_library(path)
        else:
            if path.suffix.lower() in ('.tswt', '.bin'):
                if path.stat().st_size > MAX_BYTES:
                    raise ValueError('波表文件过大。')
                data = path.read_bytes()
            elif path.suffix.lower() in ('.wt', '.wav'):
                data = encode_bank([resample_frame(f) for f in load_surge_frames(path)])
            else:
                data = encode_bank([load_table(path)])
            resources = [make_resource(1, 1, path.stem[:80], data)]
        self.library = resources
        self.tell(f'已校验 {len(resources)} 个波表资源。')
        return self.library_catalog()

    def get_pair(self, resource_id, position):
        if type(resource_id) is not int or not 0 <= resource_id < len(self.library):
            raise ValueError('请选择波表资源。')
        if type(position) not in (int, float) or not math.isfinite(position) or not 0 <= position <= 100:
            raise ValueError('波表位置应为 0–100%。')
        return self.library[resource_id].pair(position)

    def wave_preview(self, resource_id, position):
        frames, job = self.get_pair(resource_id, position)
        return dict(frames=[frame[::4] for frame in frames], **job)

    def upload_wave(self, index, resource_id, position, single=False):
        index = self.key_index(index)
        frames, job = self.get_pair(resource_id, position)
        candidate = copy.deepcopy(self.config)
        candidate['keys'][index]['synth'].update(mode='波表混合', wave_a='自定义波表', gain_a=100., gain_b=0.,
                                                frame_position=0 if single else job['fraction'] * 100 / 65535)
        candidate.get('tauri_bindings', {}).pop(str(index), None)
        self.start_resource(frames, 'library', [index], candidate, single)

    def upload_piano_wave(self, index):
        index = self.key_index(index)
        candidate = copy.deepcopy(self.config)
        candidate['keys'][index]['synth'] = dict(from_sound(piano_sound()), wave_a='自定义波表', gain_a=100., gain_b=0.)
        candidate.get('tauri_bindings', {}).pop(str(index), None)
        self.start_resource([harmonic_piano_table()], 'piano', [index], candidate, single=True)

    def upload_pcm(self, index, path):
        self.idle(connected=True)
        index = self.key_index(index)
        image = load_image(path)
        self.release_all()
        if not self.link.upload_pcm(image):
            raise ValueError('设备拒绝采样上传。')
        self.pending_resource = dict(indices=[index])
        self.transfer, self.progress, self.total = 'pcm', 0, len(image['samples'])
        self.pcm_available = False
        self.tell('正在上传 PCM 采样包…')

    def set_output(self, volume, boost):
        self.idle()
        candidate = copy.deepcopy(self.config)
        candidate['sound'].update(volume=volume, output_boost=boost)
        self.commit(candidate)
        if self.online:
            self.link.send([packet(3, 12, value=boost), packet(3, 0, value=round(volume * 65535 / 100))])
        self.tell('输出设置已保存' + ('并发送到硬件。' if self.online else '，连接后发送到硬件。'))

    def apply_template(self, sound):
        self.idle()
        candidate = copy.deepcopy(self.config)
        candidate['sound'] = copy.deepcopy(sound)
        validate_config(candidate)
        for key in candidate['keys']:
            key['synth'] = from_sound(sound)
        candidate['tauri_bindings'] = {}
        self.release_all()
        self.commit(candidate)
        self.synced.clear()
        self.tell('已覆盖全部音键音色；尚未同步。')

    def import_config(self, path):
        self.idle()
        candidate = self.validate_document(read_json(path))
        self.release_all()
        self.commit(candidate)
        self.synced.clear()
        self.tell('配置已导入；请重新同步。')

    def export_config(self, path):
        Path(path).write_text(json.dumps(self.config, ensure_ascii=False, indent=2), encoding='utf-8')
        self.tell('配置已导出。')

    def surge_connect(self, input_port=53280, output_port=53281):
        self.surge_disconnect()
        self.surge_snapshot = SurgeSnapshot()
        self.surge = OscReader(input_port, output_port)
        self.surge.start()
        self.surge_message = '等待 Surge OSC 回包…'

    def surge_disconnect(self):
        if self.surge:
            self.surge.close()
        self.surge = None
        self.surge_message = '已停止读取，保留快照。'

    def surge_data(self):
        return self.surge_snapshot.export()

    def surge_import(self, path):
        snapshot = SurgeSnapshot.from_json(read_json(path))
        self.surge_disconnect()
        self.surge_snapshot = snapshot
        self.surge_message = '已载入参数快照。'

    def surge_export(self, path):
        Path(path).write_text(json.dumps(self.surge_snapshot.export(), ensure_ascii=False, indent=2), encoding='utf-8')

    def surge_apply(self, index, scene='a'):
        self.idle()
        index = self.key_index(index)
        key = copy.deepcopy(self.config['keys'][index])
        key['synth'], notes = map_envelope(self.surge_snapshot, key['synth'], scene)
        self.save_key(index, key)
        self.tell('Surge ADSR 已保存到当前键，请同步后演奏。')
        return notes

    def tick(self):
        if self.held and time.monotonic() - self.last_ui > 1.5:
            self.release_all()
            self.tell('界面心跳超时，已释放音符。', 'error')
        if self.surge:
            for _ in range(512):
                try:
                    kind, data = self.surge.events.get_nowait()
                except queue.Empty:
                    break
                if kind == 'error':
                    self.surge_disconnect()
                    self.surge_message = str(data)
                    break
                if kind == 'messages':
                    try:
                        for address, values in data:
                            self.surge_snapshot.feed(address, values)
                        self.surge_message = '正在读取本机 Surge 参数。'
                    except ValueError as error:
                        self.surge_message = str(error)
        if self.link:
            for _ in range(256):
                try:
                    kind, data = self.link.events.get_nowait()
                except queue.Empty:
                    break
                try:
                    self.handle_event(kind, data)
                except (ValueError, OSError) as error:
                    self.transfer = None
                    self.pending_resource = None
                    self.tell(str(error), 'error')
                if self.link is None:
                    break

    def handle_event(self, kind, data):
        if kind == 'status':
            first = not self.online
            self.online = True
            self.telemetry = data
            if first:
                self.link.panic()
                self.link.send(sound_packets(self.config['sound']))
                self.link.send([packet(0x36)])
                self.tell('FPGA 已响应。请同步需要演奏的音键。', 'success')
        elif kind == 'pcm_status':
            self.pcm_available = data['available']
        elif kind.endswith('_progress') and self.transfer:
            self.progress = data
        elif kind == 'profiles_done' and self.transfer == 'profiles':
            self.synced.update(self.batch)
            self.transfer = None
            self.tell('音键参数已通过硬件校验，可以演奏。', 'success')
        elif kind == 'upload_done' and self.transfer == 'wavetable' and self.pending_resource:
            pending = self.pending_resource
            self.pending_resource = None
            self.transfer = None
            self.active_resource = pending['resource']
            # One shared pair: replacing it invalidates other custom-wave keys.
            self.synced.difference_update(i for i, k in enumerate(self.config['keys']) if self.custom(k['synth']))
            if pending['candidate'] is not None:
                self.commit(pending['candidate'])
            self.start_profiles(pending['indices'])
        elif kind == 'pcm_done' and self.transfer == 'pcm' and self.pending_resource:
            index = self.pending_resource['indices'][0]
            self.pending_resource = None
            self.transfer = None
            self.pcm_available = True
            candidate = copy.deepcopy(self.config)
            candidate['keys'][index]['synth'] = preset('采样钢琴')
            candidate.get('tauri_bindings', {}).pop(str(index), None)
            self.synced.discard(index)
            self.commit(candidate)
            self.start_profiles([index])
        elif kind.endswith('_error'):
            self.transfer = None
            self.pending_resource = None
            self.tell(str(data), 'error')
        elif kind in ('error', 'closed'):
            self.disconnect()
            self.tell(str(data) if kind == 'error' else '串口已关闭。', 'error')
        elif kind == 'overflow':
            self.held.clear()
            self.tell(str(data), 'error')

    def close(self):
        self.surge_disconnect()
        self.preview_stop()
        self.disconnect()

    def dispatch(self, method, params):
        commands = {name: getattr(self, name) for name in (
            'get_state', 'ports', 'connect', 'disconnect', 'release_all', 'panic', 'note_on', 'note_off',
            'save_key', 'bank_catalog', 'load_preset', 'preview', 'preview_stop', 'sync',
            'library_catalog', 'load_library_file', 'wave_preview', 'upload_wave', 'upload_piano_wave',
            'upload_pcm', 'set_output', 'apply_template', 'import_config', 'export_config',
            'surge_connect', 'surge_disconnect', 'surge_data', 'surge_import', 'surge_export', 'surge_apply')}
        if method not in commands or not isinstance(params, dict):
            raise ValueError('未知命令或参数格式错误。')
        return commands[method](**params)
