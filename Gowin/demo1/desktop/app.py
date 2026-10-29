"""Tang Synth 32：可映射电脑键盘的 FPGA 合成器控制桌面。"""
import json
import copy
import os
import queue
import sys
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog
import ttkbootstrap as bootstrap
from serial.tools import list_ports
from protocol import defaults, validate_config, note_name, sound_packets, packet, WAVES, PIANO, piano_sound
from transport import SerialLink
from wavetable import load_table, harmonic_piano_table, load_surge_frames, resample_frame
from surge_bridge import map_envelope
from pcm import load_image
from profiles import MODES, OSC_WAVES, PRESETS, from_sound, preset, validate_profile
from wavetable_library_ui import LibraryPanel
from basic_bank_ui import BasicBankPanel

from ui_theme import BG, PANEL, TILE, INK, MUTED, ACCENT, configure_theme, size_window
from studio_ui import StudioView
CONFIG_PATH = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'TangSynth32' / 'settings-pcm.json'


class App(bootstrap.App):
    def __init__(self):
        super().__init__(title='Tang Synth 32 · 硬件合成器工作台', theme='nord-dark',
                         iconphoto=None)
        size_window(self, 1380, 880, (1180, 800))
        self.configure(bg=BG)
        self.config_data = defaults()
        self.load_error = ''
        self.library_panel = None
        self.basic_panel = None
        self.pending_basic_patch = None
        load_path=next((p for p in (CONFIG_PATH,CONFIG_PATH.with_name('settings-perkey.json'),CONFIG_PATH.with_name('settings.json')) if p.exists()),CONFIG_PATH)
        if load_path.exists():
            try:
                self.config_data = validate_config(json.loads(load_path.read_text(encoding='utf-8')))
            except (ValueError, TypeError, KeyError, OSError) as error:
                self.load_error = f'配置未加载，已使用默认值：{error}'
        self.link = None
        self.surge_panel = None
        self.profiles_uploading=False
        self.synced_keys=set()
        self.profile_batch=[]
        self.pcm_available = False
        self.uploading = False
        self.online = False
        self.selected = 0
        self.held = {}  # 一个音键可同时由鼠标、键盘持有；最后一个来源释放才 NoteOff。
        self.keyboard_down = {}
        self.release_jobs = {}
        self.capturing = False
        self.capture_code = None
        self.mouse_index = None
        self.play_enabled = tk.BooleanVar(value=True)
        self.connection = tk.StringVar(value='未连接 · 选择 DEBUG USB 对应串口')
        self.status = tk.StringVar(value='声部 — / 32     振荡器 —     削波 —     错误 —')
        self.hint = tk.StringVar(value='左键按住发音 · 右键编辑 · Esc 紧急停止 · 键盘演奏仅在本窗口生效')
        self.configure_style()
        self.build_ui()
        self.refresh_ports()
        self.select_key(0)
        self.install_keyboard_bindings()
        self.bind_all('<ButtonRelease-1>', self.mouse_release)
        self.bind_all('<FocusOut>', lambda _: self.after(80, self.check_focus))
        self.protocol('WM_DELETE_WINDOW', self.close_app)
        self.after(30, self.poll)
        if self.load_error:
            self.after(300, lambda: messagebox.showwarning('配置', self.load_error))

    def install_keyboard_bindings(self):
        # Run before widget class handlers: mapped Space must not activate a button.
        tag = 'SynthKeyboard'
        self.bind_class(tag, '<KeyPress>', self.key_press)
        self.bind_class(tag, '<KeyRelease>', self.key_release)
        def attach(widget):
            widget.bindtags((tag,) + widget.bindtags())
            for child in widget.winfo_children():
                attach(child)
        attach(self)

    def keyboard_mode_changed(self):
        self.release_all()
        self.focus_set()
        self.hint.set('键盘演奏已启用，按音键上显示的按键即可。' if self.play_enabled.get() else '键盘演奏已关闭。')

    def configure_style(self):
        configure_theme(self)

    def build_ui(self):
        self.view = StudioView(self)

    def redraw(self):
        for i, (button, item) in enumerate(zip(self.pads, self.config_data['keys'])):
            active = bool(self.held.get(i))
            button.configure(text=f"{item['shortcut']}  ·  {i+1:02}\n{note_name(item['note'])}\n{item['synth']['mode']} {'✓' if i in self.synced_keys else '·'}",
                             bg=ACCENT if active else TILE, fg=BG if active else INK,
                             highlightbackground=ACCENT if i == self.selected else TILE)
        self.view.refresh()

    def select_key(self, index):
        self.capturing = False
        self.selected = index
        item = self.config_data['keys'][index]
        self.editor_title.configure(text=f'音键 {index+1:02} 设置')
        for name, entry in self.fields.items():
            entry.delete(0, 'end')
            entry.insert(0, str(item[name]))
        self.capture_code = item['keycode']
        self.shortcut_text.set(item['shortcut'])
        self.redraw()

    def capture(self):
        self.release_all()
        self.capturing = True
        self.capture_button.focus_set()
        self.shortcut_text.set('请按一个键… Esc 取消')

    def apply_key(self):
        try:
            candidate = json.loads(json.dumps(self.config_data))
            item = candidate['keys'][self.selected]
            item.update(name=self.fields['name'].get().strip(), note=int(self.fields['note'].get()),
                        velocity=int(self.fields['velocity'].get()), keycode=self.capture_code,
                        shortcut=self.shortcut_text.get())
            validate_config(candidate)
            self.release_all()
            self.config_data = candidate
            self.save_config()
            self.select_key(self.selected)
            self.focus_set()
            self.hint.set('音键配置已应用并保存。')
        except (ValueError, TypeError, OSError) as error:
            messagebox.showerror('音键配置', str(error))

    def upload_all_profiles(self):
        self.upload_profiles(list(range(32)))

    def open_surge_panel(self):
        if self.surge_panel is not None and self.surge_panel.winfo_exists():
            self.surge_panel.lift()
            return
        from surge_panel import SurgePanel
        self.release_all()
        self.surge_panel = SurgePanel(self)

    def apply_surge_envelope(self, snapshot, scene='a'):
        if self.uploading or self.profiles_uploading:
            raise ValueError('请等待当前上传结束后再应用 Surge 参数。')
        index = self.selected
        profile, _ = map_envelope(snapshot, self.config_data['keys'][index]['synth'], scene)
        self.release_all()
        previous = self.config_data
        candidate = json.loads(json.dumps(previous))
        candidate['keys'][index]['synth'] = profile
        self.config_data = validate_config(candidate)
        try:
            self.save_config()
        except OSError:
            self.config_data = previous
            raise
        self.synced_keys.discard(index)
        self.redraw()
        self.hint.set('Surge 音量包络已保存到当前键；其余参数保持原设置。')
        if self.online:
            self.upload_profiles([index])

    def upload_profiles(self, indices):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接 FPGA，并等待当前上传结束。')
            return False
        batch=[(32+i,dict(self.config_data['keys'][i]['synth'],frame_position=self.config_data['keys'][i]['synth'].get('frame_position',0))) for i in indices]
        self.release_all()
        if self.link.upload_profiles(batch):
            self.profile_batch=list(indices)
            self.synced_keys.difference_update(indices)
            self.profiles_uploading=True
            self.hint.set('正在校验并上传逐键参数…')
            self.redraw()
            return True
        return False

    def edit_synth(self):
        if self.uploading or self.profiles_uploading:
            self.hint.set('等待上传结束后再编辑参数。')
            return
        self.release_all()
        index=self.selected
        dialog=tk.Toplevel(self);dialog.title(f'音键 {index+1:02} · 合成器参数')
        dialog.configure(bg=PANEL);dialog.transient(self);dialog.grab_set()
        form=ttk.Frame(dialog,padding=16);form.pack(fill='both',expand=True)
        controls={}
        fields=[('mode','合成模式'),('wave_a','载波 A'),('wave_b','调制波 B'),('ratio','B:A 频率比'),
                ('depth','深度：FM周期 / AM比例'),('mod_hz','B 固定 Hz（0=频率比）'),('sensitivity','力度→深度 %'),
                ('gain_a','A 音量 %'),('gain_b','混合模式 B 音量 %'),('frame_position','双帧位置 %（下次起音）'),
                ('attack','音量 A / ms'),('decay','音量 D / ms'),('sustain','音量 S / %'),('release','音量 R / ms'),
                ('m_attack','调制 A / ms'),('m_decay','调制 D / ms'),('m_sustain','调制 S / %'),('m_release','调制 R / ms')]
        choices={'mode':list(MODES),'wave_a':list(OSC_WAVES),'wave_b':list(OSC_WAVES)}
        for row,(name,label) in enumerate(fields):
            ttk.Label(form,text=label).grid(row=row//2,column=(row%2)*2,sticky='w',padx=5,pady=4)
            if name in choices:widget=ttk.Combobox(form,values=choices[name],state='readonly',width=19)
            else:widget=ttk.Entry(form,width=21)
            widget.grid(row=row//2,column=(row%2)*2+1,sticky='ew',padx=5,pady=4)
            controls[name]=widget
        def fill(patch):
            for name,widget in controls.items():
                if isinstance(widget,ttk.Combobox):widget.set(str(patch[name]))
                else:widget.delete(0,'end');widget.insert(0,str(patch.get(name,0)))
        fill(self.config_data['keys'][index]['synth'])
        presets=ttk.Combobox(form,values=list(PRESETS),state='readonly',width=19);presets.set(PRESETS[0])
        presets.grid(row=9,column=0,columnspan=2,pady=8)
        ttk.Button(form,text='载入预设到编辑框',command=lambda:fill(preset(presets.get()))).grid(row=9,column=2,columnspan=2)
        ttk.Label(form,text='FM 深度以周期计。采样钢琴仅使用 A 音量、音量 ADSR 与按键力度。').grid(row=10,column=0,columnspan=4,pady=8)
        def save(upload=False):
            try:
                patch={name:(widget.get() if name in choices else float(widget.get())) for name,widget in controls.items()}
                validate_profile(patch)
                if patch['frame_position']==0:patch.pop('frame_position')
                self.config_data['keys'][index]['synth']=patch
                self.synced_keys.discard(index);self.save_config();self.redraw()
                dialog.destroy();self.focus_set()
                self.hint.set('此键参数已保存到电脑，尚未上传。')
                if upload:self.upload_profiles([index])
            except (ValueError,OSError) as error:messagebox.showerror('合成器参数',str(error),parent=dialog)
        ttk.Button(form,text='仅保存',command=lambda:save(False)).grid(row=11,column=1,pady=8)
        ttk.Button(form,text='保存并上传此键',command=lambda:save(True)).grid(row=11,column=2,columnspan=2,pady=8)
        dialog.bind('<Escape>',lambda _:dialog.destroy())

    def apply_piano(self):
        # Keep all user key mappings and current applied volume.
        preset = piano_sound(self.config_data['sound']['volume'])
        for name, var in self.sound_vars.items():
            var.set(preset[name])
        self.wave.set(PIANO)
        self.release_all()
        self.apply_sound()

    def apply_volume(self):
        try:
            value = float(self.sound_vars['volume'].get())
            if not 0 <= value <= 100:
                raise ValueError('总音量必须在 0..100 范围内')
            self.config_data['sound']['volume'] = value
            boost = self.output_boost.current()
            if not 0 <= boost <= 4:
                raise ValueError('请选择输出增益档位。')
            self.config_data['sound']['output_boost'] = boost
            self.save_config()
            if self.online:
                self.link.send([packet(3, 12, value=boost), packet(3, 0, value=round(value*65535/100))])
            self.hint.set('总音量与输出增益已应用，逐键音色保持不变。')
            self.focus_set()
        except (ValueError, tk.TclError, OSError) as error:
            messagebox.showerror('总音量', str(error))

    def apply_sound(self):
        if self.uploading or self.profiles_uploading:
            self.hint.set('等待上传结束后再应用模板。');return
        try:
            candidate = json.loads(json.dumps(self.config_data))
            candidate['sound'] = {name: round(var.get(), 2) for name, var in self.sound_vars.items()}
            candidate['sound']['wave'] = self.wave.get()
            candidate['sound']['output_boost'] = self.output_boost.current()
            validate_config(candidate)
            for key in candidate['keys']:key['synth']=from_sound(candidate['sound'])
            self.config_data = candidate
            self.synced_keys.clear()
            if self.online:
                self.link.send(sound_packets(candidate['sound']))
            self.save_config()
            self.redraw()
            self.hint.set('全部音键模板已保存。')
            if self.online:self.upload_all_profiles()
            self.focus_set()
        except (ValueError, TypeError, tk.TclError, OSError) as error:
            messagebox.showerror('音色参数', str(error))

    def upload_pcm_file(self):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接采样版 FPGA，并等待当前上传结束。');return
        folder=(Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).parent)/'samples'
        path=filedialog.askopenfilename(title='真实起音＋循环尾音 PCM 采样',initialdir=str(folder),filetypes=[('PCM 采样包','*.json')])
        if path:
            try:self.start_pcm_upload(load_image(path))
            except (ValueError,OSError) as error:messagebox.showerror('钢琴采样',str(error))

    def start_pcm_upload(self, image):
        if not self.online or self.uploading or self.profiles_uploading:return
        self.panic()
        if self.link.upload_pcm(image):
            self.uploading=True;self.pcm_available=False
            self.pcm_target=self.selected;self.pcm_total=len(image['samples'])
            self.hint.set('上传真实采样到 RAM；当前采样暂停，完成后切换选中键。')

    def upload_table_file(self):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接 FPGA，且等待当前上传结束。')
            return
        path=filedialog.askopenfilename(title='单周期波表 / Surge 导出的 WAV',filetypes=[('波表','*.wt *.wav *.json *.csv *.txt')])
        if path:
            try:
                if Path(path).suffix.lower() in ('.wt', '.wav'):
                    frames = load_surge_frames(path)
                    index = 0
                    if len(frames) > 1:
                        index = simpledialog.askinteger('选择波表帧', f'文件含 {len(frames)} 帧。硬件目前只能存一个周期，请选择帧号（从 0 开始）：', initialvalue=0, minvalue=0, maxvalue=len(frames)-1, parent=self)
                    if index is None:
                        return
                    self.start_table_upload(resample_frame(frames[index]))
                else:
                    self.start_table_upload(load_table(path))
            except (ValueError, OSError) as error:
                messagebox.showerror('波表',str(error))

    def upload_piano_table(self):
        self.start_table_upload(harmonic_piano_table(), piano=True)

    def upload_pair_file(self):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接 FPGA，且等待当前上传结束。');return
        path=filedialog.askopenfilename(title='选择 Surge 双帧波表工作集',filetypes=[('Surge 波表','*.wt *.wav')])
        if not path:return
        try:
            frames=load_surge_frames(path)
            if len(frames)<2:raise ValueError('文件至少需要两帧；单帧请使用“导入波表”。')
            index=simpledialog.askinteger('相邻双帧',f'文件共 {len(frames)} 帧。选择前帧编号，后帧自动使用下一帧（从0开始）：',initialvalue=0,minvalue=0,maxvalue=len(frames)-2,parent=self)
            if index is None:return
            self.start_pair_upload([resample_frame(frames[index]),resample_frame(frames[index+1])])
        except (ValueError,OSError) as error:messagebox.showerror('双帧波表',str(error))

    def open_library_panel(self):
        if self.library_panel is not None and self.library_panel.winfo_exists():
            self.library_panel.lift();return
        self.release_all()
        folder=(Path(sys.executable).parent/'wavetable_library' if getattr(sys,'frozen',False)
                else Path(__file__).resolve().parents[1]/'output/sd_library_demo')
        self.library_panel=LibraryPanel(self,self.start_pair_upload,folder,
                                      lambda:setattr(self,'library_panel',None))

    def open_basic_panel(self):
        if self.basic_panel is not None and self.basic_panel.winfo_exists():
            self.basic_panel.lift();return
        self.release_all()
        folder=(Path(sys.executable).parent/'basic_bank' if getattr(sys,'frozen',False)
                else Path(__file__).resolve().parents[1]/'output/basic_bank_v1')
        panel=BasicBankPanel(self,self.apply_basic_timbre,folder,
                             lambda:setattr(self,'basic_panel',None))
        self.basic_panel=panel
        try:panel.load(folder)
        except (ValueError,OSError,TypeError) as error:
            panel.status.set('随附音色库加载失败，可手动选择 BASICS.JSN：'+str(error))

    def store_key_profile(self, index, profile):
        previous=self.config_data
        candidate=copy.deepcopy(previous)
        candidate['keys'][index]['synth']=copy.deepcopy(profile)
        self.config_data=validate_config(candidate)
        try:self.save_config()
        except OSError:
            self.config_data=previous
            raise
        self.synced_keys.discard(index)
        return previous

    def apply_basic_timbre(self, profile, frames=None):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接 FPGA，并等待当前上传结束。');return False
        profile=copy.deepcopy(validate_profile(profile))
        custom='自定义波表' in (profile['wave_a'],profile['wave_b'])
        if profile['mode']=='采样钢琴' or custom!=(frames is not None):
            raise ValueError('基础音色参数与波表资源不一致')
        if frames is not None:
            if not self.start_pair_upload(frames,0):return False
            self.pending_basic_patch=(self.table_target,profile)
            return True
        index=self.selected
        synced=set(self.synced_keys)
        previous=self.store_key_profile(index,profile)
        try:
            if self.upload_profiles([index]):return True
        except (ValueError,OSError):
            self.config_data=previous;self.synced_keys=synced;self.save_config()
            raise
        self.config_data=previous;self.synced_keys=synced;self.save_config()
        self.hint.set('参数发送队列未接受音色，原配置已恢复。')
        return False

    def start_pair_upload(self, frames, frame_fraction=None):
        if not self.online or self.uploading or self.profiles_uploading:return False
        if frame_fraction is not None and (type(frame_fraction) is not int or not 0<=frame_fraction<=65535):
            raise ValueError('帧位置必须是 uint16')
        self.release_all()
        if self.link.upload_pair(frames):
            self.pending_basic_patch=None
            self.uploading=True;self.table_piano=False;self.table_target=self.selected;self.table_total=2048
            self.table_fraction=frame_fraction
            self.hint.set('正在上传共享双帧波表；完成前暂停演奏。可在逐键参数中设置双帧位置。')
            return True
        return False

    def start_table_upload(self, samples, piano=False):
        if not self.online or self.uploading or self.profiles_uploading:
            self.hint.set('请先连接 FPGA，且等待当前上传结束。')
            return
        self.release_all()
        if self.link.upload(samples):
            self.pending_basic_patch=None
            self.uploading=True
            self.table_piano=piano
            self.table_target=self.selected
            self.table_total=1024
            self.table_fraction=None
            self.hint.set('正在上传到共享波表 RAM；完成前暂停演奏。所有自定义波表键都会使用新表。')

    def press(self, index, source):
        if self.uploading or self.profiles_uploading:
            return
        if index not in self.synced_keys:
            self.hint.set('此键参数尚未确认上传，请点击“上传此键参数”或“上传全部参数”。');return
        if not self.online:
            self.hint.set('尚未收到 FPGA 状态：请先连接 DEBUG USB 对应串口。')
            return
        if self.config_data['keys'][index]['synth']['mode']=='采样钢琴' and not self.pcm_available:
            self.hint.set('请先用“导入钢琴采样”上传 PCM 采样包。');return
        held = self.held.setdefault(index, set())
        if source in held:
            return
        if not held:
            item = self.config_data['keys'][index]
            if not self.link.send([packet(1, 32+index, item['note'], item['velocity'])]):
                self.held.pop(index, None)
                return
        held.add(source)
        self.redraw()

    def release(self, index, source):
        held = self.held.get(index)
        if not held:
            return
        held.discard(source)
        if not held:
            self.held.pop(index, None)
            if self.online:
                self.link.send([packet(2, 32+index)])
        self.redraw()

    def mouse_press(self, index):
        self.focus_set()
        self.select_key(index)
        self.mouse_index = index
        self.press(index, 'mouse')

    def mouse_release(self, _):
        if self.mouse_index is not None:
            self.release(self.mouse_index, 'mouse')
            self.mouse_index = None

    def key_press(self, event):
        code = event.keycode
        if self.capturing:
            if code == 27:
                self.select_key(self.selected)
            elif code not in (16, 17, 18, 91, 92):
                self.capture_code = code
                self.shortcut_text.set(event.keysym.upper())
                self.capturing = False
            return 'break'
        if code == 27:
            self.panic()
            return 'break'
        if code in self.release_jobs:
            self.after_cancel(self.release_jobs.pop(code))
        if code in self.keyboard_down:
            return
        # Windows Tk: Mod1 (0x08) is NumLock, Mod2 (0x10) is Alt.
        # Do not apply the X11 Alt mask on Windows.
        if (self.view.current_page != 'perform' or not self.play_enabled.get() or event.state & (0x20014 if self.tk.call('tk', 'windowingsystem') == 'win32' else 0x000C)
                or isinstance(event.widget, (ttk.Entry, ttk.Combobox, tk.Entry, tk.Text, ttk.Spinbox, tk.Spinbox))):
            return
        for index, item in enumerate(self.config_data['keys']):
            if item['keycode'] == code:
                self.keyboard_down[code] = index
                self.press(index, 'keyboard')
                if index in self.held:
                    self.hint.set(f"键盘 {item['shortcut']} → 音键 {index+1:02} · {note_name(item['note'])}")
                return 'break'

    def key_release(self, event):
        code = event.keycode
        if code in self.keyboard_down:
            if code in self.release_jobs:
                self.after_cancel(self.release_jobs[code])
            self.release_jobs[code] = self.after(12, lambda: self.finish_release(code))
            return 'break'

    def finish_release(self, code):
        self.release_jobs.pop(code, None)
        index = self.keyboard_down.pop(code, None)
        if index is not None:
            self.release(index, 'keyboard')

    def release_all(self):
        if self.online and self.held:
            self.link.send([packet(2, 32+i) for i in self.held])
        self.clear_held()

    def clear_held(self):
        for job in self.release_jobs.values():
            self.after_cancel(job)
        self.release_jobs.clear()
        self.keyboard_down.clear()
        self.held.clear()
        self.mouse_index = None
        self.redraw()

    def panic(self):
        if self.link:
            self.link.panic()
        self.clear_held()
        self.hint.set('已请求紧急停止全部声部。' if self.online else '已清除本地按键状态。')

    def check_focus(self):
        if self.focus_displayof() is None:
            self.release_all()

    def refresh_ports(self):
        self.port_map = {f'{p.device} · {p.description}': p.device for p in list_ports.comports()}
        self.port['values'] = list(self.port_map)
        if self.port.get() not in self.port_map:
            self.port.set(next(iter(self.port_map), ''))

    def toggle_connection(self):
        if self.link:
            self.disconnect()
            return
        selected = self.port_map.get(self.port.get())
        if not selected:
            messagebox.showinfo('串口', '请插入 DEBUG USB 数据线，刷新并选择串口。')
            return
        self.link = SerialLink(selected)
        self.connection.set('打开串口，等待 FPGA 状态…')
        self.connect_button.configure(text='断开')
        self.link.start()
        self.focus_set()

    def disconnect(self):
        self.pending_basic_patch=None
        self.uploading=False
        self.profiles_uploading=False
        self.synced_keys.clear()
        self.online = False
        self.pcm_available = False
        if self.link:
            self.link.close()
            self.link = None
        self.clear_held()
        self.connect_button.configure(text='连接')
        self.connection.set('未连接')
        self.status.set('声部 — / 32     振荡器 —     削波 —     错误 —')

    def poll(self):
        if self.link:
            while True:
                try:
                    kind, data = self.link.events.get_nowait()
                except queue.Empty:
                    break
                if kind == 'status':
                    if not self.online:
                        self.online = True
                        self.link.panic()
                        self.link.send(sound_packets(self.config_data['sound']))
                        self.link.send([packet(0x36)])
                        self.upload_all_profiles()
                    self.connection.set('已连接 · FPGA 已响应 · 115200')
                    errors = data['flags'] & 0x0F
                    self.status.set(f"声部 {data['voices']} / 32    振荡器 {data['oscillators']}    削波 {data['clips']}    错误 0x{errors:02X}    帧周期 {data['cycles']}")
                elif kind == 'pcm_status':
                    self.pcm_available=data['available']
                elif kind == 'pcm_progress':
                    self.hint.set(f"PCM 采样已确认 {data}/{self.pcm_total}；传输期间暂停演奏。")
                elif kind == 'pcm_done':
                    self.uploading=False;self.pcm_available=True;self.clear_held()
                    index=self.pcm_target
                    self.config_data['keys'][index]['synth']=preset('采样钢琴')
                    self.synced_keys.discard(index)
                    try:self.save_config()
                    except OSError as error:messagebox.showerror('保存配置',str(error))
                    self.upload_profiles([index])
                elif kind == 'pcm_error':
                    self.uploading=False;self.pcm_available=False;self.clear_held();self.hint.set(str(data))
                elif kind == 'profiles_progress':
                    self.hint.set(f'逐键参数已确认 {data}/{len(self.profile_batch)}')
                elif kind == 'profiles_done':
                    self.profiles_uploading=False
                    self.synced_keys.update(self.profile_batch)
                    self.clear_held()
                    self.hint.set('逐键参数已由 FPGA 校验确认，下次起音生效。')
                elif kind == 'profiles_error':
                    self.profiles_uploading=False
                    self.clear_held()
                    self.hint.set(str(data))
                elif kind == 'upload_progress':
                    self.hint.set(f'波表上传 {data}/{getattr(self,"table_total",1024)}；等待 CRC 校验与空闲帧切换。')
                elif kind == 'upload_done':
                    if not self.uploading:continue
                    self.uploading=False
                    self.clear_held()
                    index=self.table_target
                    pending=self.pending_basic_patch;self.pending_basic_patch=None
                    if pending is not None:
                        if pending[0]!=index:
                            self.hint.set('波表已提交，但目标键不匹配，未应用音色参数。');continue
                        patch=pending[1]
                    else:
                        patch=copy.deepcopy(self.config_data['keys'][index]['synth'])
                        if self.table_piano:patch=from_sound(piano_sound(self.config_data['sound']['volume']))
                        patch.update(mode='波表混合',wave_a='自定义波表',gain_a=100.,gain_b=0.)
                        fraction=getattr(self,'table_fraction',None)
                        if fraction is not None:patch['frame_position']=fraction*100/65535
                    # The resource and key profile have separate confirmations.
                    self.synced_keys.discard(index)
                    try:self.store_key_profile(index,patch)
                    except OSError as error:
                        self.hint.set('波表已提交，但参数保存失败；此键未确认，请重试：'+str(error));continue
                    if not self.upload_profiles([index]):
                        self.hint.set('波表已提交，但键参数尚未发送，请重试上传此键参数。')
                elif kind == 'upload_error':
                    self.pending_basic_patch=None
                    self.uploading=False
                    self.clear_held()
                    self.hint.set(str(data))
                elif kind in ('error', 'overflow'):
                    self.clear_held()
                    self.hint.set(str(data))
                    if kind == 'error':
                        self.online = False
                elif kind == 'closed':
                    self.disconnect()
                    break
        self.view.refresh()
        self.after(30, self.poll)

    def save_config(self):
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        temporary = CONFIG_PATH.with_suffix('.tmp')
        temporary.write_text(json.dumps(self.config_data, ensure_ascii=False, indent=2), encoding='utf-8')
        temporary.replace(CONFIG_PATH)

    def export_config(self):
        self.release_all()
        path = filedialog.asksaveasfilename(defaultextension='.json', initialfile='tang-synth-32.json', filetypes=[('配置', '*.json')])
        if path:
            try:
                Path(path).write_text(json.dumps(self.config_data, ensure_ascii=False, indent=2), encoding='utf-8')
            except OSError as error:
                messagebox.showerror('导出失败', str(error))

    def import_config(self):
        if self.uploading or self.profiles_uploading:
            self.hint.set('等待上传结束后再导入配置。')
            return
        self.release_all()
        path = filedialog.askopenfilename(filetypes=[('配置', '*.json')])
        if path:
            try:
                candidate = validate_config(json.loads(Path(path).read_text(encoding='utf-8')))
                self.panic()
                self.config_data = candidate
                for name, var in self.sound_vars.items():
                    var.set(candidate['sound'][name])
                self.wave.set(candidate['sound']['wave'])
                self.output_boost.current(candidate['sound']['output_boost'])
                self.select_key(0)
                self.synced_keys.clear()
                self.redraw()
                self.save_config()
                if self.online:
                    self.link.send(sound_packets(candidate['sound']))
                    self.upload_all_profiles()
            except (ValueError, TypeError, KeyError, OSError) as error:
                messagebox.showerror('导入失败', str(error))

    def close_app(self):
        if self.basic_panel is not None:
            self.basic_panel.close()
        if self.library_panel is not None:
            self.library_panel.close()
        if self.surge_panel is not None:
            self.surge_panel.close()
        self.disconnect()
        self.destroy()


if __name__ == '__main__':
    App().mainloop()
