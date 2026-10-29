"""Studio presentation layer. Device/patch operations remain on App."""
import tkinter as tk
import ttkbootstrap as ttk

from protocol import WAVES, note_name
from ui_theme import BG, PANEL, TILE, INK, MUTED, ACCENT, BORDER, WARNING, FONT
from ui_theme import label, card, EnvelopePreview, scale_size


class StudioView:
    PAGES = {
        'perform': ('演奏工作台', '选择音键，编辑音色，再同步到硬件。'),
        'resources': ('音色与资源', '从基础音色开始，导入波表与采样，或连接 Surge。'),
        'settings': ('全局与模板', '调整整体输出，或为全部音键应用统一模板。'),
    }

    def __init__(self, app):
        self.app = app
        self.current_page = 'perform'
        self._state = None
        self.pages, self.nav_buttons = {}, {}
        shell = tk.Frame(app, bg=BG)
        shell.pack(fill='both', expand=True, padx=20, pady=18)
        shell.columnconfigure(1, weight=1)
        shell.rowconfigure(0, weight=1)
        sidebar = tk.Frame(shell, bg=BG, width=scale_size(app, 180))
        sidebar.grid(row=0, column=0, sticky='ns', padx=(0, 20))
        sidebar.pack_propagate(False)
        label(sidebar, 'TS / 32', 28, ACCENT).pack(anchor='w', pady=(2, 0))
        label(sidebar, 'TANG SYNTH', 11).pack(anchor='w')
        label(sidebar, '硬件合成器工作台', 9, MUTED).pack(anchor='w', pady=(6, 32))
        for key, number, title in [('perform', '01', '演奏工作台'),
                                   ('resources', '02', '音色与资源'),
                                   ('settings', '03', '全局与模板')]:
            button = tk.Button(sidebar, text=f'{number}   {title}', anchor='w',
                               font=(FONT, 11), relief='flat', bd=0, padx=12, pady=13,
                               cursor='hand2', command=lambda p=key: self.show_page(p))
            button.pack(fill='x', pady=3)
            self.nav_buttons[key] = button
        bottom = tk.Frame(sidebar, bg=BG)
        bottom.pack(side='bottom', fill='x')
        label(bottom, '配置文件', 9, MUTED).pack(anchor='w', pady=(0, 8))
        ttk.Button(bottom, text='导入配置', command=app.import_config,
                   bootstyle='secondary outline').pack(fill='x', pady=(0, 8))
        ttk.Button(bottom, text='导出配置', command=app.export_config,
                   bootstyle='secondary outline').pack(fill='x')
        tk.Frame(bottom, bg=BORDER, height=1).pack(fill='x', pady=22)
        label(bottom, 'TANG MEGA 60K', 10).pack(anchor='w')
        label(bottom, '32 音键 · DEBUG USB', 9, MUTED).pack(anchor='w', pady=(5, 0))

        workspace = tk.Frame(shell, bg=BG)
        workspace.grid(row=0, column=1, sticky='nsew')
        workspace.columnconfigure(0, weight=1)
        workspace.rowconfigure(2, weight=1)
        header = tk.Frame(workspace, bg=BG)
        header.grid(row=0, column=0, sticky='ew', pady=(0, 16))
        titles = tk.Frame(header, bg=BG)
        titles.pack(side='left')
        self.title = label(titles, size=23)
        self.title.pack(anchor='w')
        self.subtitle = label(titles, size=10, color=MUTED)
        self.subtitle.pack(anchor='w', pady=(4, 0))
        ttk.Button(header, text='紧急停止  Esc', command=app.panic,
                   bootstyle='danger outline').pack(side='right')
        self.build_connection(workspace)
        self.content = tk.Frame(workspace, bg=BG)
        self.content.grid(row=2, column=0, sticky='nsew', pady=14)
        self.content.columnconfigure(0, weight=1)
        self.content.rowconfigure(0, weight=1)
        for key in self.PAGES:
            page = tk.Frame(self.content, bg=BG)
            page.grid(row=0, column=0, sticky='nsew')
            self.pages[key] = page
        self.build_performance(self.pages['perform'])
        self.build_resources(self.pages['resources'])
        self.build_settings(self.pages['settings'])
        footer = tk.Frame(workspace, bg=BG)
        footer.grid(row=3, column=0, sticky='ew')
        label(footer, textvariable=app.status, size=9, color=ACCENT).pack(anchor='w')
        hint = label(footer, textvariable=app.hint, size=9, color=MUTED, justify='left')
        hint.pack(fill='x', pady=(6, 0))
        footer.bind('<Configure>', lambda e: hint.configure(wraplength=max(200, e.width)))
        self.show_page('perform', initial=True)

    def build_connection(self, parent):
        app = self.app
        bar = card(parent, 12)
        bar.grid(row=1, column=0, sticky='ew')
        bar.columnconfigure(1, weight=1)
        self.device_badge = label(bar, '●  离线', 10, MUTED)
        self.device_badge.grid(row=0, column=0, padx=(0, 16), sticky='w')
        app.port = ttk.Combobox(bar, state='readonly', width=30)
        app.port.grid(row=0, column=1, sticky='ew')
        ttk.Button(bar, text='刷新', command=app.refresh_ports,
                   bootstyle='secondary outline').grid(row=0, column=2, padx=8)
        app.connect_button = ttk.Button(bar, text='连接', command=app.toggle_connection,
                                        bootstyle='primary')
        app.connect_button.grid(row=0, column=3)
        self.sync_button = ttk.Button(bar, text='同步全部音键', command=app.upload_all_profiles,
                                       bootstyle='secondary outline')
        self.sync_button.grid(row=0, column=4, padx=(14, 0))
        label(bar, textvariable=app.connection, size=9, color=MUTED).grid(
            row=1, column=0, columnspan=4, sticky='w', pady=(8, 0))
        self.sync_count = label(bar, '0 / 32 已同步', 9, MUTED)
        self.sync_count.grid(row=1, column=4, sticky='e', pady=(8, 0))

    def build_performance(self, page):
        app = self.app
        page.columnconfigure(0, weight=1)
        page.columnconfigure(1, minsize=scale_size(app, 300))
        page.rowconfigure(0, weight=1)
        pads = card(page, 16)
        pads.grid(row=0, column=0, sticky='nsew', padx=(0, 14))
        header = tk.Frame(pads, bg=PANEL)
        header.pack(fill='x', pady=(0, 6))
        label(header, '音键矩阵', 15).pack(side='left')
        ttk.Checkbutton(header, text='键盘演奏', variable=app.play_enabled,
                        command=app.keyboard_mode_changed,
                        bootstyle='primary round-toggle').pack(side='right')
        label(pads, '左键按住发音 · 右键选择编辑', 9, MUTED).pack(anchor='w', pady=(0, 14))
        grid = tk.Frame(pads, bg=PANEL)
        grid.pack(fill='both', expand=True)
        app.pads = []
        for index in range(32):
            button = tk.Button(grid, relief='flat', bd=0, bg=TILE, fg=INK,
                               activebackground=ACCENT, activeforeground=BG,
                               font=(FONT, 10), cursor='hand2', takefocus=False,
                               highlightthickness=2, highlightbackground=TILE)
            button.grid(row=index // 8, column=index % 8, padx=3, pady=4, sticky='nsew')
            button.bind('<ButtonPress-1>', lambda _, i=index: app.mouse_press(i))
            button.bind('<ButtonPress-3>', lambda _, i=index: app.select_key(i))
            app.pads.append(button)
            grid.columnconfigure(index % 8, weight=1, uniform='pads')
            grid.rowconfigure(index // 8, weight=1, minsize=scale_size(app, 65))
        label(pads, '✓ 已由硬件确认     · 待同步     绿色边框 = 当前编辑音键',
              9, MUTED).pack(anchor='w', pady=(12, 0))
        ttk.Button(pads, text='浏览基础音色库', command=app.open_basic_panel,
                   bootstyle='secondary outline').pack(anchor='w', pady=(12, 0))

        editor = card(page, 16)
        editor.grid(row=0, column=1, sticky='nsew')
        app.editor_title = label(editor, '音键 01 设置', 15)
        app.editor_title.pack(anchor='w')
        self.key_state = label(editor, color=WARNING, size=9)
        self.key_state.pack(anchor='w', pady=(3, 10))
        self.patch_summary = label(editor, size=10)
        self.patch_summary.pack(anchor='w')
        self.envelope = EnvelopePreview(editor, 72)
        self.envelope.pack(fill='x', pady=(8, 0))
        self.envelope_values = label(editor, size=8, color=MUTED)
        self.envelope_values.pack(anchor='w', pady=(4, 10))
        app.fields = {}
        form = tk.Frame(editor, bg=PANEL)
        form.pack(fill='x')
        form.columnconfigure(1, weight=1)
        for row, (name, title) in enumerate([('name', '名称'), ('note', '音高 0–127'),
                                            ('velocity', '力度 1–127')]):
            label(form, title, 9, MUTED).grid(row=row, column=0, sticky='w', padx=(0, 8), pady=3)
            entry = ttk.Entry(form, width=15)
            entry.grid(row=row, column=1, sticky='ew', pady=3)
            app.fields[name] = entry
        mapping = tk.Frame(editor, bg=PANEL)
        mapping.pack(fill='x', pady=(8, 10))
        label(mapping, '键盘映射', 9, MUTED).pack(side='left')
        app.shortcut_text = tk.StringVar()
        app.capture_button = ttk.Button(mapping, textvariable=app.shortcut_text,
                                        command=app.capture, width=13,
                                        bootstyle='secondary outline')
        app.capture_button.pack(side='right')
        actions = tk.Frame(editor, bg=PANEL)
        actions.pack(fill='x')
        ttk.Button(actions, text='应用映射', command=app.apply_key,
                   bootstyle='secondary outline').pack(side='left', fill='x', expand=True)
        ttk.Button(actions, text='音色参数', command=app.edit_synth,
                   bootstyle='secondary outline').pack(side='left', fill='x', expand=True, padx=(6, 0))
        self.upload_key = ttk.Button(editor, text='同步此键音色', bootstyle='primary',
                                      command=lambda: app.upload_profiles([app.selected]))
        self.upload_key.pack(fill='x', pady=(10, 0))

    def build_resources(self, page):
        page.columnconfigure((0, 1), weight=1, uniform='resource')
        page.rowconfigure((1, 2), weight=1)
        self.resource_target = label(page, size=10, color=ACCENT)
        self.resource_target.grid(row=0, column=0, columnspan=2, sticky='w', pady=(0, 12))
        a = self.app
        groups = [
            ('01 / PRESETS', '基础音色库', '16 个入门音色，支持电脑参考试听。\n选择音色后应用到当前音键。',
             [('浏览与试听', a.open_basic_panel)]),
            ('02 / WAVETABLE', '波表工作区', '浏览资源、预览相邻帧与混合位置。\n当前固件的自定义波表共用一对帧。',
             [('资源库', a.open_library_panel), ('导入单帧', a.upload_table_file),
              ('导入双帧', a.upload_pair_file), ('谐波钢琴表', a.upload_piano_table)]),
            ('03 / SAMPLE', '钢琴采样', '导入带真实起音与循环尾音的 PCM 包。\n需要连接支持采样的 FPGA 固件。',
             [('导入采样包', a.upload_pcm_file)]),
            ('04 / BRIDGE', 'Surge 参数桥接', '接收 Surge 参数并检查映射结果。\n目前可将音量包络应用到当前音键。',
             [('打开参数桥接', a.open_surge_panel)]),
        ]
        for i, (eyebrow, title, description, actions) in enumerate(groups):
            section = card(page)
            section.grid(row=1 + i // 2, column=i % 2, sticky='nsew',
                         padx=(0, 7) if i % 2 == 0 else (7, 0),
                         pady=(0, 7) if i < 2 else (7, 0))
            label(section, eyebrow, 9, ACCENT).pack(anchor='w')
            label(section, title, 19).pack(anchor='w', pady=(8, 8))
            details = label(section, description, 10, MUTED, justify='left')
            details.pack(fill='x')
            section.bind('<Configure>', lambda e, w=details: w.configure(wraplength=max(180, e.width - 38)))
            buttons = tk.Frame(section, bg=PANEL)
            buttons.pack(side='bottom', anchor='w', pady=(12, 0))
            for j, (text, callback) in enumerate(actions):
                ttk.Button(buttons, text=text, command=callback,
                           bootstyle='primary' if j == 0 else 'secondary outline').grid(
                    row=j // 2, column=j % 2, sticky='w', padx=(0, 8), pady=(6, 0))

    def build_settings(self, page):
        a = self.app
        page.columnconfigure(0, minsize=scale_size(a, 260))
        page.columnconfigure(1, weight=1)
        page.rowconfigure(0, weight=1)
        output = card(page)
        output.grid(row=0, column=0, sticky='nsew', padx=(0, 14))
        label(output, 'MASTER / 输出', 10, ACCENT).pack(anchor='w')
        label(output, '总音量', 19).pack(anchor='w', pady=(10, 18))
        a.sound_vars = {key: tk.DoubleVar(value=a.config_data['sound'][key])
                        for key in ('attack', 'decay', 'sustain', 'release', 'volume')}
        ttk.Entry(output, textvariable=a.sound_vars['volume'], width=10).pack(anchor='w')
        label(output, '音量 / %', 9, MUTED).pack(anchor='w', pady=(6, 0))
        ttk.Scale(output, from_=0, to=100, variable=a.sound_vars['volume']).pack(fill='x', pady=(10, 24))
        label(output, '输出增益', 10).pack(anchor='w', pady=(0, 8))
        a.output_boost = ttk.Combobox(output, values=('0 dB · ×1', '+6 dB · ×2', '+12 dB · ×4',
                                                     '+18 dB · ×8', '+24 dB · ×16'),
                                     state='readonly', width=19)
        a.output_boost.current(a.config_data['sound'].get('output_boost', 0))
        a.output_boost.pack(fill='x')
        ttk.Button(output, text='应用输出设置', command=a.apply_volume,
                   bootstyle='primary').pack(fill='x', pady=(18, 14))
        label(output, '只调整整体输出。\n增益用于补偿混音余量，\n请关注底部的削波计数。',
              9, MUTED, justify='left').pack(anchor='w')

        template = card(page)
        template.grid(row=0, column=1, sticky='nsew')
        label(template, 'TEMPLATE / 全部音键', 10, WARNING).pack(anchor='w')
        row = tk.Frame(template, bg=PANEL)
        row.pack(fill='x', pady=(10, 12))
        label(row, '音色模板', 19).pack(side='left')
        a.wave = ttk.Combobox(row, values=list(WAVES), state='readonly', width=17)
        a.wave.set(a.config_data['sound']['wave'])
        a.wave.pack(side='right')
        self.template_envelope = EnvelopePreview(template, 82)
        self.template_envelope.pack(fill='x')
        label(template, 'ADSR 阶段示意 · 横轴非时间等比', 8, MUTED).pack(anchor='w', pady=(5, 12))
        form = tk.Frame(template, bg=PANEL)
        form.pack(fill='x')
        form.columnconfigure(1, weight=1)
        for i, (name, text, maximum) in enumerate([('attack', 'A  起音 / ms', 2000),
                                                  ('decay', 'D  衰减 / ms', 2000),
                                                  ('sustain', 'S  持续 / %', 100),
                                                  ('release', 'R  释放 / ms', 3000)]):
            label(form, text, 10, MUTED).grid(row=i, column=0, sticky='w', padx=(0, 12), pady=8)
            ttk.Scale(form, from_=0, to=maximum, variable=a.sound_vars[name]).grid(row=i, column=1, sticky='ew')
            ttk.Entry(form, textvariable=a.sound_vars[name], width=8).grid(row=i, column=2, padx=(14, 0))
            a.sound_vars[name].trace_add('write', self.update_template_preview)
        self.update_template_preview()
        label(template, '应用模板会覆盖全部 32 键的独立音色。', 10, WARNING).pack(anchor='w', pady=(16, 8))
        actions = tk.Frame(template, bg=PANEL)
        actions.pack(fill='x')
        ttk.Button(actions, text='钢琴模板并应用', command=a.apply_piano,
                   bootstyle='secondary outline').pack(side='left')
        ttk.Button(actions, text='覆盖全部并同步', command=a.apply_sound,
                   bootstyle='warning outline').pack(side='right')

    def update_template_preview(self, *_):
        try:
            values = {k: self.app.sound_vars[k].get() for k in ('attack', 'decay', 'sustain', 'release')}
        except (tk.TclError, ValueError):
            return  # A temporarily empty numeric field is valid while editing.
        self.template_envelope.show(values)

    def show_page(self, name, initial=False):
        if name not in self.pages:
            raise ValueError('Unknown studio page: ' + name)
        if not initial:
            self.app.release_all()
            if self.app.capturing:
                self.app.select_key(self.app.selected)
            self.app.focus_set()
        self.current_page = name
        for key, page in self.pages.items():
            if key == name:
                page.grid()
            else:
                page.grid_remove()
            self.nav_buttons[key].configure(
                bg=TILE if key == name else BG, fg=ACCENT if key == name else MUTED,
                activebackground=TILE, activeforeground=INK)
        self.title.configure(text=self.PAGES[name][0])
        self.subtitle.configure(text=self.PAGES[name][1])

    def refresh(self):
        a = self.app
        item = a.config_data['keys'][a.selected]
        profile = item['synth']
        state = (a.online, bool(a.link), a.uploading, a.profiles_uploading,
                 tuple(sorted(a.synced_keys)), a.selected, item['note'], tuple(sorted(profile.items())))
        if state == self._state:
            return
        self._state = state
        busy = a.uploading or a.profiles_uploading
        self.device_badge.configure(text='●  在线' if a.online else ('●  等待响应' if a.link else '●  离线'),
                                    fg=ACCENT if a.online else MUTED)
        self.sync_count.configure(text=f'{len(a.synced_keys)} / 32 已同步')
        for button in (self.sync_button, self.upload_key):
            button.configure(state='normal' if a.online and not busy else 'disabled')
        confirmed = a.online and a.selected in a.synced_keys
        self.key_state.configure(text='已由硬件确认' if confirmed else '传输中 · 暂停演奏' if busy else '本地音色 · 待同步',
                                 fg=ACCENT if confirmed else WARNING)
        self.patch_summary.configure(text=f"{profile['mode']}  /  {profile['wave_a']}")
        self.envelope.show(profile)
        self.envelope_values.configure(text=f"A {profile['attack']:g}  D {profile['decay']:g}  S {profile['sustain']:g}%  R {profile['release']:g}  · 阶段示意")
        self.resource_target.configure(text=f"应用目标：音键 {a.selected + 1:02} · {note_name(item['note'])}    |    返回演奏页可更换目标")
