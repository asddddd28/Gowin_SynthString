"""独立的 Surge 参数查看窗口；读取和应用到硬件分成两个明确动作。"""
import json
import queue
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

from surge_bridge import OscReader, SurgeSnapshot, map_envelope
from ui_theme import style_text, size_window


class SurgePanel(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title('Surge 参数桥接 · 读取软件 / 配置硬件音键')
        size_window(self, 1000, 760, (850, 680))
        self.reader = None
        self.snapshot = SurgeSnapshot()
        self.scene = tk.StringVar(value='A')
        self.state = tk.StringVar(value='未连接。先在 Surge 主菜单的 OSC 设置开启输入及输出。')
        self.target = tk.StringVar()
        self.inputs = {}
        frame = ttk.Frame(self, padding=14)
        frame.pack(fill='both', expand=True)
        ttk.Label(frame, text='Surge 输入 53280；输出目标 127.0.0.1:53281。本窗口只连接本机。').pack(anchor='w')
        bar = ttk.Frame(frame)
        bar.pack(fill='x', pady=8)
        for key, label, value in (('input', 'Surge 输入端口', 53280), ('output', '本窗口接收端口', 53281)):
            ttk.Label(bar, text=label).pack(side='left', padx=(0, 5))
            entry = ttk.Entry(bar, width=7)
            entry.insert(0, str(value))
            entry.pack(side='left', padx=(0, 12))
            self.inputs[key] = entry
        self.connect_button = ttk.Button(bar, text='连接读取', command=self.toggle)
        self.connect_button.pack(side='left')
        ttk.Button(bar, text='重新读取', command=self.refresh).pack(side='left', padx=8)
        ttk.Label(frame, textvariable=self.state, wraplength=940).pack(anchor='w')
        commands = ttk.Frame(frame)
        commands.pack(fill='x', pady=10)
        ttk.Label(commands, text='场景').pack(side='left')
        scene = ttk.Combobox(commands, textvariable=self.scene, values=('A', 'B'), state='readonly', width=4)
        scene.pack(side='left', padx=8)
        scene.bind('<<ComboboxSelected>>', lambda _: self.render())
        ttk.Button(commands, text='导出参数快照', command=self.export_snapshot).pack(side='right')
        ttk.Button(commands, text='载入参数快照', command=self.import_snapshot).pack(side='right', padx=8)
        self.tree = ttk.Treeview(frame, columns=('address', 'value', 'mapping'), show='headings', height=12)
        for name, label, width in (('address', '软件参数地址', 390), ('value', '软件读数', 230), ('mapping', '当前硬件映射', 220)):
            self.tree.heading(name, text=label)
            self.tree.column(name, width=width, stretch=True)
        scroll = ttk.Scrollbar(frame, orient='vertical', command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        listing = ttk.Frame(frame)
        listing.pack(fill='both', expand=True)
        self.tree.pack(in_=listing, side='left', fill='both', expand=True)
        scroll.pack(in_=listing, side='right', fill='y')
        ttk.Label(frame, textvariable=self.target).pack(anchor='w', pady=(12, 4))
        self.preview = tk.Text(frame, height=7, wrap='word', relief='flat', background='#edf3fc')
        style_text(self.preview)
        self.preview.pack(fill='x')
        ttk.Button(frame, text='应用 A/D/S/R 到当前音键并上传', command=self.apply).pack(anchor='e', pady=(8, 0))
        self.protocol('WM_DELETE_WINDOW', self.close)
        self.last_target = None
        self.job = self.after(40, self.poll)
        self.render()

    def stop_reader(self):
        if self.reader:
            self.reader.close()
            self.reader = None
        self.connect_button.configure(text='连接读取')

    def toggle(self):
        if self.reader:
            self.stop_reader()
            self.state.set('已停止读取。保留当前快照供查看或保存。')
            return
        try:
            self.reader = OscReader(int(self.inputs['input'].get()), int(self.inputs['output'].get()))
            self.snapshot = SurgeSnapshot()
            self.reader.start()
            self.connect_button.configure(text='停止读取')
            self.state.set('等待 Surge 回包；若参数数为零，请检查软件 OSC 输入、输出与端口。')
            self.render()
        except (ValueError, OSError) as error:
            self.stop_reader()
            messagebox.showerror('Surge 连接', str(error), parent=self)

    def refresh(self):
        if not self.reader:
            self.state.set('请先连接 Surge。')
            return
        try:
            # 先丢弃尚未消费的旧包，再发起新的只读查询。
            while not self.reader.events.empty():
                try:
                    self.reader.events.get_nowait()
                except queue.Empty:
                    break
            self.snapshot = SurgeSnapshot()
            self.reader.query()
            self.state.set('重新读取中。OSC 通过 UDP 传输，必要字段缺失时不会应用到音键。')
            self.render()
        except OSError as error:
            self.stop_reader()
            self.state.set(str(error))

    def poll(self):
        changed = self.last_target != self.master.selected
        if self.reader:
            try:
                for _ in range(512):
                    kind, data = self.reader.events.get_nowait()
                    if kind == 'error':
                        self.snapshot = SurgeSnapshot()
                        self.stop_reader()
                        self.state.set(str(data))
                        changed = True
                        break
                    for address, values in data:
                        if address == '/error':
                            self.state.set('Surge 返回：' + ' '.join(map(str, values)))
                        elif self.snapshot.feed(address, values):
                            self.reader.query()
                        changed = True
                    self.state.set(f'已收到 {len(self.snapshot.parameters)} 个参数。停止调节软件后再应用；快照不是原子音色导出。')
            except queue.Empty:
                pass
            except (ValueError, OSError) as error:
                self.snapshot = SurgeSnapshot()
                self.stop_reader()
                self.state.set(str(error))
                changed = True
        if changed:
            self.render()
        self.job = self.after(40, self.poll)

    def render(self):
        scene = self.scene.get().lower()
        self.last_target = self.master.selected
        prefix = '/param/' + scene + '/aeg/'
        self.tree.delete(*self.tree.get_children())
        for address, data in sorted(self.snapshot.parameters.items()):
            if address.startswith('/param/' + ('b' if scene == 'a' else 'a') + '/'):
                continue
            mapped = address in {prefix + field for field in ('attack', 'decay', 'sustain', 'release')}
            self.tree.insert('', 'end', values=(address, data['display'] or str(data['value']), '可导入音量包络' if mapped else '仅查看；尚未自动映射'))
        item = self.master.config_data['keys'][self.master.selected]
        self.target.set(f"当前目标：音键 {self.master.selected + 1:02} · {item['name']} · MIDI {item['note']}，其他键保持原配置。")
        try:
            result, notes = map_envelope(self.snapshot, item['synth'], scene)
            text = f"A {result['attack']:.3f} ms   D {result['decay']:.3f} ms   S {result['sustain']:.3f}%   R {result['release']:.3f} ms\n\n" + '\n'.join(notes)
        except ValueError as error:
            text = '当前不能应用：' + str(error)
        self.preview.configure(state='normal')
        self.preview.delete('1.0', 'end')
        self.preview.insert('1.0', text)
        self.preview.configure(state='disabled')

    def apply(self):
        try:
            self.master.apply_surge_envelope(self.snapshot, self.scene.get().lower())
            self.render()
        except (ValueError, OSError) as error:
            messagebox.showerror('包络映射', str(error), parent=self)

    def export_snapshot(self):
        path = filedialog.asksaveasfilename(parent=self, defaultextension='.json', initialfile='surge-parameters.json', filetypes=[('Surge 参数快照', '*.json')])
        if path:
            try:
                Path(path).write_text(json.dumps(self.snapshot.export(), ensure_ascii=False, indent=2), encoding='utf-8')
            except OSError as error:
                messagebox.showerror('保存快照', str(error), parent=self)

    def import_snapshot(self):
        path = filedialog.askopenfilename(parent=self, filetypes=[('Surge 参数快照', '*.json')])
        if path:
            try:
                source = Path(path)
                if source.stat().st_size > 4 * 1024 * 1024:
                    raise ValueError('参数快照超过 4 MiB。')
                candidate = SurgeSnapshot.from_json(json.loads(source.read_text(encoding='utf-8-sig')))
                self.stop_reader()
                self.snapshot = candidate
                self.state.set('已载入离线快照；可查看并应用包络。')
                self.render()
            except (ValueError, OSError) as error:
                messagebox.showerror('载入快照', str(error), parent=self)

    def close(self):
        self.after_cancel(self.job)
        self.stop_reader()
        self.master.surge_panel = None
        self.destroy()
