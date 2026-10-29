"""Tang Keyboard Lab: live 4x8 hall keyboard monitor and software calibration."""
from __future__ import annotations

import argparse
import csv
import json
import os
import queue
import sys
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from keyboard_core import CalibrationSession, KeyboardState, Profile, StreamParser
from transport import Reader, ports
from board_protocol import BoardLink, calibration_commands, EFFECT, QUERY, GAME_START, GAME_STOP
from games_ui import GamesPanel

BG = "#0b1220"
PANEL = "#111d30"
CARD = "#17263c"
LINE = "#293b54"
TEXT = "#e4edf8"
MUTED = "#8da3bf"
CYAN = "#53d6d1"
GREEN = "#73e6a6"
AMBER = "#ffc473"
FONT = "Microsoft YaHei UI"
EFFECTS = ['0 · 关闭灯光', '1 · 单键亮起约1秒（并行）', '2 · 彩色涟漪扩散（打断）', '3 · 快速整板流水（打断）', '4 · 十字扩散（打断）']


def resource(name):
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent)) / name


class Matrix(tk.Canvas):
    def __init__(self, parent, selected):
        super().__init__(parent, bg=BG, highlightthickness=0, height=390)
        self.selected_callback = selected
        self.cells = []
        self.boxes = []
        self.bind("<Configure>", self.layout)
        self.bind("<Button-1>", self.click)

    def layout(self, event=None):
        self.delete("all")
        self.cells, self.boxes = [], []
        width, height = max(self.winfo_width(), 600), max(self.winfo_height(), 180)
        left, top, gap = 28, 25, 9
        cw = (width - left - 7 * gap - 2) / 8
        ch = (height - top - 3 * gap - 2) / 4
        for col in range(8):
            self.create_text(left + col * (cw + gap) + cw / 2, 10, text=str(col + 1), fill=MUTED, font=(FONT, 9))
        for row in range(4):
            self.create_text(10, top + row * (ch + gap) + ch / 2, text=str(row + 1), fill=MUTED, font=(FONT, 9))
        for key in range(32):
            row, col = divmod(key, 8)
            x, y = left + col * (cw + gap), top + row * (ch + gap)
            box = self.create_rectangle(x, y, x + cw, y + ch, fill=CARD, outline=LINE, width=1)
            title = self.create_text(x + 10, y + 14, text=f"K{key + 1:02d}", anchor="w", fill=MUTED, font=(FONT, 10, "bold"))
            compact = ch < 78
            badge = self.create_text(x + cw - 9, y + ch * .60 if compact else y + 14,
                                     text="", anchor="e", fill=GREEN, font=(FONT, 9),
                                     state="hidden" if ch < 48 else "normal")
            value = self.create_text(x + 10, y + ch * (.60 if compact else .49), text="—", anchor="w", fill=TEXT,
                                     font=(FONT, max(12, min(18, int(ch * .23))), "bold"), state="hidden" if ch < 48 else "normal")
            raw = self.create_text(x + cw - 8 if compact else x + 10, y + 14 if compact else y + ch - 20,
                                   text="等待数据", anchor="e" if compact else "w", fill=MUTED, font=(FONT, 7 if compact else 9))
            self.create_rectangle(x + 10, y + ch - 8, x + cw - 10, y + ch - 5, fill=LINE, outline="")
            bar = self.create_rectangle(x + 10, y + ch - 8, x + 10, y + ch - 5, fill=CYAN, outline="")
            self.cells.append((box, title, badge, value, raw, bar))
            self.boxes.append((x, y, cw, ch))

    def click(self, event):
        for index, (x, y, w, h) in enumerate(self.boxes):
            if x <= event.x <= x + w and y <= event.y <= y + h:
                self.selected_callback(index)
                return

    def refresh(self, model, selected, now):
        for i, (box, title, badge, value, raw, bar) in enumerate(self.cells):
            fresh = model.fresh(i, now)
            depth = model.depth(i, now)
            pressed = model.pressed[i] and fresh
            x, y, w, h = self.boxes[i]
            self.itemconfigure(box, fill="#164035" if pressed else CARD,
                               outline=CYAN if selected == i else LINE, width=2 if selected == i else 1)
            self.itemconfigure(title, fill=GREEN if pressed else MUTED)
            text = f"{depth * 100:.0f}%" if depth is not None else "未校准" if fresh else "—"
            self.itemconfigure(value, text=text, fill=GREEN if pressed else TEXT if fresh else MUTED)
            rv = model.raw[i]
            raw_text = (f"{rv:04d}" if w < 95 else f"ADC {rv:04d}") if rv is not None and fresh else ("离线" if w < 95 else "数据超时" if rv is not None else "等待数据")
            self.itemconfigure(raw, text=raw_text)
            candidate = model.session and i + 1 in model.session.bottom and model.session.stage == "press"
            self.itemconfigure(badge, text="✓" if candidate else "●" if pressed else "")
            self.coords(bar, x + 10, y + h - 8, x + 10 + (w - 20) * (depth or 0), y + h - 5)
            self.itemconfigure(bar, fill=GREEN if pressed else CYAN)


class KeyboardApp:
    def __init__(self, root, args):
        self.root, self.args = root, args
        self.root.title("Tang Keyboard Lab · 键盘校准")
        width = min(1360, self.root.winfo_screenwidth() - 80)
        height = min(850, self.root.winfo_screenheight() - 100)
        self.root.geometry(f"{width}x{height}")
        self.root.minsize(1100, 740)
        self.root.configure(bg=BG)
        self.state_dir = args.state_dir or Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "TangKeyboardLab"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.profile_path = self.state_dir / "calibration.json"
        self.profile_message = ""
        profile = Profile.empty()
        path = args.profile or (self.profile_path if self.profile_path.exists() else resource("measured_profile.json"))
        if path.exists():
            try:
                profile = Profile.load(path)
            except (ValueError, OSError, TypeError) as exc:
                self.profile_message = f"配置未加载：{exc}"
        self.model = KeyboardState(profile)
        self.parser = StreamParser()
        self.reader = None
        self.input_kind = "none"
        self.source_label = "未连接"
        self.input_ready = False
        self.selected = 0
        self.last_diag = self.last_graph = self.last_rate = 0
        self.previous_records = self.previous_scans = self.queue_dropped = 0
        self.rate_records = self.rate_scans = 0
        self.record_file = self.csv_writer = None
        self.record_start = 0
        self.closing = False
        self.board = None
        self.need_sync = False
        self.auto_sync_pending = False
        self.game_status = None
        self.game_updated = float('-inf')
        self.effect_settings = {'mode': 1, 'direction': 0}
        try:
            settings = json.loads((self.state_dir / 'effects.json').read_text(encoding='utf-8'))
            if type(settings.get('mode')) is int and settings['mode'] in range(5) and type(settings.get('direction')) is int and settings['direction'] in (0, 1):
                self.effect_settings = settings
        except (OSError, ValueError, TypeError, AttributeError):
            pass
        self._style()
        self._build()
        if getattr(args,'games',False):
            self.notebook.select(self.games_page)
        self.refresh_ports()
        self.update_profile_label()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.report_callback_exception = self.callback_error
        self.root.after(35, self.tick)
        if args.port:
            self.root.after(300, lambda: self.connect(args.port))
        elif args.replay:
            self.root.after(300, lambda: self.open_replay(args.replay))
        if args.quit_after:
            self.root.after(int(args.quit_after * 1000), self.close)

    def _style(self):
        self.root.option_add("*Font", (FONT, 10))
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame", background=BG)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("TLabel", background=BG, foreground=TEXT, font=(FONT, 10))
        style.configure("Panel.TLabel", background=PANEL, foreground=TEXT)
        style.configure("Muted.TLabel", background=BG, foreground=MUTED, font=(FONT, 9))
        style.configure("TButton", background=CARD, foreground=TEXT, borderwidth=0, padding=(12, 8), font=(FONT, 10))
        style.map("TButton", background=[("active", "#263e59"), ("disabled", "#152033")], foreground=[("disabled", "#61728a")])
        style.configure("Accent.TButton", background=CYAN, foreground=BG)
        style.map("Accent.TButton", background=[("active", "#84eae5"), ("disabled", "#1f4550")], foreground=[("disabled", MUTED)])
        style.configure("TCombobox", fieldbackground=CARD, background=CARD, foreground=TEXT, arrowcolor=TEXT, padding=6)
        style.map("TCombobox", fieldbackground=[("readonly", CARD)], foreground=[("readonly", TEXT)])
        style.configure("TProgressbar", background=CYAN, troughcolor=CARD, borderwidth=0, thickness=6)
        style.configure("TSpinbox", fieldbackground=CARD, foreground=TEXT, arrowcolor=TEXT, background=CARD, padding=5)
        style.configure('TNotebook',background=BG,borderwidth=0)
        style.configure('TNotebook.Tab',background=CARD,foreground=MUTED,padding=(20,9))
        style.map('TNotebook.Tab',background=[('selected',PANEL)],foreground=[('selected',CYAN)])

    def label(self, parent, text, size=10, color=TEXT, bg=BG, **kwargs):
        return tk.Label(parent, text=text, bg=bg, fg=color, font=(FONT, size), **kwargs)

    def _build(self):
        header = tk.Frame(self.root, bg=BG)
        header.pack(fill="x", padx=26, pady=(18, 12))
        self.label(header, "TANG  /  KEYBOARD LAB", 10, CYAN).pack(anchor="w")
        self.label(header, "键盘实验室 · 校准 / 灯效 / 小游戏", 23).pack(side="left", pady=(5, 0))
        self.label(header, "32 KEYS   ·   HALL SENSOR   ·   12-BIT ADC", 10, MUTED).pack(side="right", pady=(10, 0))
        toolbar = tk.Frame(self.root, bg=PANEL, padx=14, pady=10)
        toolbar.pack(fill="x", padx=26)
        self.connection_label = self.label(toolbar, "● 未连接", 10, MUTED, PANEL, width=16, anchor="w")
        self.connection_label.pack(side="left")
        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(toolbar, textvariable=self.port_var, state="readonly", width=34)
        self.port_combo.pack(side="left", padx=(0, 8))
        ttk.Button(toolbar, text="刷新", command=self.refresh_ports).pack(side="left", padx=(0, 8))
        self.connect_button = ttk.Button(toolbar, text="连接", style="Accent.TButton", command=self.toggle_connection)
        self.connect_button.pack(side="left", padx=(0, 12))
        self.label(toolbar, "115200 · 8N1", 9, MUTED, PANEL).pack(side="left")
        self.record_button = ttk.Button(toolbar, text="录制 CSV", command=self.toggle_recording)
        self.record_button.pack(side="right", padx=(8, 0))
        ttk.Button(toolbar, text="打开历史回放", command=self.choose_replay).pack(side="right")
        self.notebook = ttk.Notebook(self.root)
        self.calibration_page = tk.Frame(self.notebook,bg=BG)
        self.notebook.add(self.calibration_page,text='校准与灯效')
        self.games_page = GamesPanel(self.notebook,self.start_game,self.stop_game)
        self.notebook.add(self.games_page,text='小游戏')
        content = tk.Frame(self.calibration_page, bg=BG)
        content.pack(fill="both", expand=True, pady=(12,0))
        content.columnconfigure(0, weight=1)
        content.columnconfigure(1, minsize=328)
        content.rowconfigure(0, weight=1)
        left = tk.Frame(content, bg=BG)
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 22))
        title = tk.Frame(left, bg=BG)
        title.pack(fill="x")
        self.label(title, "键盘矩阵", 15).pack(side="left")
        self.label(title, "4 × 8 · 点击按键查看曲线    青色：选中   绿色：触发", 9, MUTED).pack(side="right")
        self.matrix = Matrix(left, self.select_key)
        self.matrix.pack(fill="both", expand=True, pady=(7, 12))
        detail = tk.Frame(left, bg=PANEL, padx=16, pady=12)
        detail.pack(fill="x")
        self.detail_title = self.label(detail, "K01 / 第1行 · 第1列", 13, CYAN, PANEL, anchor="w")
        self.detail_title.pack(fill="x")
        self.detail_text = self.label(detail, "等待数据", 10, MUTED, PANEL, anchor="w")
        self.detail_text.pack(fill="x", pady=(6, 0))
        self.chart = tk.Canvas(left, height=100, bg=PANEL, highlightthickness=0)
        self.chart.pack(fill="x", pady=(1, 0))
        self.events_label = self.label(left, "按键事件会显示在这里", 9, MUTED, anchor="w")
        self.events_label.pack(fill="x", pady=(10, 0))
        # Reserve the detail/chart area before giving remaining height to the matrix.
        self.matrix.pack_forget()
        detail.pack_forget()
        self.chart.pack_forget()
        self.events_label.pack_forget()
        self.events_label.pack(side="bottom", fill="x", pady=(10, 0))
        self.chart.pack(side="bottom", fill="x", pady=(1, 0))
        detail.pack(side="bottom", fill="x")
        self.matrix.pack(fill="both", expand=True, pady=(7, 12))
        rail = tk.Frame(content, bg=PANEL)
        rail.grid(row=0, column=1, sticky="nsew")
        self.rail_canvas = tk.Canvas(rail, bg=PANEL, highlightthickness=0, width=328)
        scroll = ttk.Scrollbar(rail, orient="vertical", command=self.rail_canvas.yview)
        self.rail_canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.rail_canvas.pack(side="left", fill="both", expand=True)
        side = tk.Frame(self.rail_canvas, bg=PANEL, padx=17, pady=15)
        window = self.rail_canvas.create_window((0, 0), window=side, anchor="nw")
        side.bind("<Configure>", lambda event: self.rail_canvas.configure(scrollregion=self.rail_canvas.bbox("all")))
        self.rail_canvas.bind("<Configure>", lambda event: self.rail_canvas.itemconfigure(window, width=event.width))
        def scroll_rail(event):
            widget = self.root.winfo_containing(event.x_root, event.y_root)
            if widget is not None and (str(widget).startswith(str(side)) or widget == self.rail_canvas):
                self.rail_canvas.yview_scroll(-int(event.delta / 120), "units")
        self.root.bind("<MouseWheel>", scroll_rail, add="+")
        self.label(side, 'FPGA 按键灯效', 16, TEXT, PANEL, anchor='w').pack(fill='x')
        self.effect_var = tk.StringVar(value=EFFECTS[self.effect_settings['mode']])
        ttk.Combobox(side, textvariable=self.effect_var, values=EFFECTS, state='readonly').pack(fill='x', pady=(9, 5))
        self.direction_var = tk.StringVar(value=['从左到右', '从上到下'][self.effect_settings['direction']])
        ttk.Combobox(side, textvariable=self.direction_var, values=['从左到右', '从上到下'], state='readonly').pack(fill='x', pady=4)
        self.effect_button = ttk.Button(side, text='发送灯效 / 流水方向', command=self.send_effect)
        self.effect_button.pack(fill='x', pady=4)
        self.sync_button = ttk.Button(side, text='下发32键校准与阈值', command=self.request_sync)
        self.sync_button.pack(fill='x', pady=4)
        self.board_label = self.label(side, '等待板卡协议确认', 9, AMBER, PANEL, anchor='w', justify='left', wraplength=290)
        self.board_label.pack(fill='x', pady=(5, 15))
        self.label(side, "校准采集", 16, TEXT, PANEL, anchor="w").pack(fill="x")
        self.profile_label = self.label(side, "", 9, MUTED, PANEL, anchor="w", justify="left", wraplength=290)
        self.profile_label.pack(fill="x", pady=(6, 14))
        self.scope_var = tk.StringVar(value="全部32键")
        ttk.Combobox(side, textvariable=self.scope_var, values=["全部32键", "仅选中键"], state="readonly").pack(fill="x", pady=(0, 9))
        self.rest_button = ttk.Button(side, text="1  采集松开位置 · 2秒", command=self.begin_rest)
        self.rest_button.pack(fill="x", pady=4)
        self.bottom_button = ttk.Button(side, text="2  记录按到底位置", command=self.begin_bottom)
        self.bottom_button.pack(fill="x", pady=4)
        self.apply_button = ttk.Button(side, text="3  应用并保存校准", style="Accent.TButton", command=self.apply_calibration)
        self.apply_button.pack(fill="x", pady=4)
        self.progress = ttk.Progressbar(side, maximum=32)
        self.progress.pack(fill="x", pady=(12, 8))
        self.cal_label = self.label(side, "全部松开按键，再采集零点。\n随后逐键按到底，完成后应用。", 10, MUTED, PANEL,
                                    justify="left", anchor="nw", wraplength=290, height=4)
        self.cal_label.pack(fill="x")
        self.cancel_button = ttk.Button(side, text="取消本轮校准", command=self.cancel_calibration)
        self.cancel_button.pack(fill="x", pady=(0, 15))
        self.label(side, "触发与释放", 12, TEXT, PANEL, anchor="w").pack(fill="x")
        thresholds = tk.Frame(side, bg=PANEL)
        thresholds.pack(fill="x", pady=8)
        self.press_var = tk.StringVar(value=f"{self.model.profile.press_threshold * 100:g}")
        self.release_var = tk.StringVar(value=f"{self.model.profile.release_threshold * 100:g}")
        self.label(thresholds, "触发 %", 9, MUTED, PANEL).grid(row=0, column=0, sticky="w")
        self.label(thresholds, "释放 %", 9, MUTED, PANEL).grid(row=0, column=1, sticky="w", padx=(15, 0))
        ttk.Spinbox(thresholds, from_=1, to=100, width=8, textvariable=self.press_var).grid(row=1, column=0, pady=4)
        ttk.Spinbox(thresholds, from_=0, to=99, width=8, textvariable=self.release_var).grid(row=1, column=1, padx=(15, 0), pady=4)
        ttk.Button(side, text="应用阈值", command=self.apply_thresholds).pack(fill="x")
        profiles = tk.Frame(side, bg=PANEL)
        profiles.pack(fill="x", pady=(15, 8))
        profiles.columnconfigure((0, 1), weight=1)
        ttk.Button(profiles, text="保存配置…", command=self.save_profile).grid(row=0, column=0, sticky="ew", padx=(0, 4))
        ttk.Button(profiles, text="读取配置…", command=self.load_profile).grid(row=0, column=1, sticky="ew", padx=(4, 0))
        self.label(side, "校准在电脑保存，并下发FPGA的RAM。\n板上判定按键；重连后自动同步。\n深度为相对值，不代表毫米距离。", 9, MUTED, PANEL,
                   justify="left", anchor="w", wraplength=290).pack(fill="x", pady=(8, 0))
        self.notice_var = tk.StringVar(value=self.profile_message or "选择 DEBUG 串口后连接。建议装配变化后重新校准。")
        self.notice = tk.Label(self.root, textvariable=self.notice_var, bg=BG, fg=AMBER, font=(FONT, 10), anchor="w")
        self.notice.pack(fill="x", padx=26, pady=(0, 6))
        self.stats_var = tk.StringVar(value="未连接 · 不会向调试器发送控制命令")
        self.label_status = tk.Label(self.root, textvariable=self.stats_var, bg="#08101c", fg=MUTED, font=(FONT, 9), anchor="w", padx=26, pady=10)
        self.label_status.pack(fill="x")
        # Pack bottom status before expandable content so it cannot be pushed offscreen.
        content.pack_forget()
        self.notice.pack_forget()
        self.label_status.pack_forget()
        self.label_status.pack(side="bottom", fill="x")
        self.notice.pack(side="bottom", fill="x", padx=26, pady=(0, 6))
        content.pack(fill="both", expand=True, pady=(12,0))
        self.notebook.pack(fill='both',expand=True,padx=26,pady=12)

    def select_key(self, index):
        self.selected = index

    def refresh_ports(self):
        try:
            self.port_choices = {f"{p.device}  ·  {p.description}": p.device for p in ports()}
            previous = self.port_var.get()
            self.port_combo.configure(values=list(self.port_choices))
            if previous not in self.port_choices:
                self.port_var.set(next(iter(self.port_choices), ""))
        except Exception as exc:
            self.notice_var.set(f"串口枚举失败：{exc}")

    def toggle_connection(self):
        if self.reader:
            self.disconnect()
        else:
            port = self.port_choices.get(self.port_var.get())
            if not port:
                self.notice_var.set("没有可用串口，请连接 DEBUG USB 后刷新。")
                return
            self.connect(port)

    def _start_reader(self, reader, kind, label):
        self.disconnect(quiet=True)
        self.model.reset_stream()
        self.parser = StreamParser()
        self.previous_records = self.previous_scans = self.queue_dropped = 0
        self.last_rate = time.monotonic()
        self.rate_records = self.rate_scans = 0
        self.reader, self.input_kind, self.source_label = reader, kind, label
        self.board = BoardLink(reader.send) if kind == 'live' else None
        self.auto_sync_pending = kind == 'live'
        self.need_sync = False
        self.input_ready = False
        self.connect_button.configure(text="断开")
        self.port_combo.configure(state="disabled")
        self.notice_var.set("正在打开数据源…")
        reader.start()

    def connect(self, port):
        self._start_reader(Reader(port=port), "live", port)

    def disconnect(self, quiet=False):
        if self.reader:
            self.reader.stop()
            if self.reader.thread.is_alive():
                raise RuntimeError("串口尚未释放，请稍后重试")
        self.reader = None
        self.board = None
        self.need_sync = False
        self.auto_sync_pending = False
        self.game_updated = float('-inf')
        self.input_ready = False
        self.input_kind = "none"
        self.model.reset_stream()
        self.stop_recording()
        self.connect_button.configure(text="连接")
        self.port_combo.configure(state="readonly")
        if not quiet:
            self.notice_var.set("已断开，按下状态已清除，串口已释放。")

    def choose_replay(self):
        path = filedialog.askopenfilename(parent=self.root, title="打开历史采集（回放，不连接FPGA）", filetypes=[("键盘原始数据", "*.bin *.txt"), ("所有文件", "*.*")])
        if path:
            self.open_replay(Path(path))

    def open_replay(self, path):
        self._start_reader(Reader(replay=path), "replay", Path(path).name)

    def update_profile_label(self):
        profile = self.model.profile
        count = sum(k is not None for k in profile.keys)
        self.profile_label.configure(text=f"{profile.name}\n{count}/32 键已校准")
        self.press_var.set(f"{profile.press_threshold * 100:g}")
        self.release_var.set(f"{profile.release_threshold * 100:g}")

    def begin_rest(self):
        if self.game_mode():
            self.notice_var.set('请先在小游戏页结束游戏，再进行校准。')
            return
        now = time.monotonic()
        targets = [self.selected + 1] if self.scope_var.get() == "仅选中键" else list(range(1, 33))
        if self.input_kind != "live" or not self.input_ready or not all(self.model.fresh(k - 1, now) for k in targets):
            self.notice_var.set("请先连接实时串口，并确认校准范围内所有按键都有新数据。")
            return
        self.model.session = CalibrationSession(targets, now)
        self.notice_var.set("正在采集松开位置：请保持全部目标按键松开2秒。原配置保留至应用完成。")

    def begin_bottom(self):
        session = self.model.session
        now = time.monotonic()
        if not session or not all(self.model.fresh(k - 1, now) for k in session.targets):
            self.notice_var.set("数据不完整，不能开始终点采集。")
            return
        session.start_press(now)
        self.notice_var.set("依次把目标按键按到底并保持至少0.3秒，然后松开；顺序不限，全部完成后应用。")

    def apply_calibration(self):
        session = self.model.session
        now = time.monotonic()
        if not session or not all(self.model.fresh(k - 1, now) for k in session.targets):
            self.notice_var.set("实时数据已中断，本轮校准不能应用。")
            return
        session.tick(now)
        try:
            candidate = session.apply(self.model.profile, "实时校准 · " + datetime.now().strftime("%m-%d %H:%M"), f"{self.source_label} / 115200 / endpoint calibration")
            candidate.save(self.profile_path)
            self.model.set_profile(candidate)
            self.model.session = None
            self.update_profile_label()
            self.notice_var.set(f"校准已应用并保存：{len(session.targets)}键。后续会自动加载此配置。")
            self.need_sync = True
        except (ValueError, OSError) as exc:
            self.notice_var.set(f"校准未应用，原配置保留：{exc}")

    def cancel_calibration(self):
        self.model.session = None
        self.notice_var.set("本轮候选校准已取消，原配置保留。")

    def apply_thresholds(self):
        try:
            old = self.model.profile
            candidate = Profile(list(old.keys), old.name, old.source, float(self.press_var.get()) / 100, float(self.release_var.get()) / 100)
            candidate.validate()
            candidate.save(self.profile_path)
            self.model.set_profile(candidate)
            self.update_profile_label()
            self.notice_var.set("触发/释放阈值已更新并保存。")
            self.need_sync = True
        except (ValueError, OSError) as exc:
            self.notice_var.set(f"阈值未更改：{exc}")

    def save_profile(self):
        path = filedialog.asksaveasfilename(parent=self.root, title="保存校准配置", defaultextension=".json", initialfile="keyboard_calibration.json", filetypes=[("校准配置", "*.json")])
        if path:
            try:
                self.model.profile.save(path)
                self.notice_var.set(f"已保存：{Path(path).name}")
            except (OSError, ValueError) as exc:
                self.notice_var.set(f"保存失败：{exc}")

    def load_profile(self):
        if self.model.session:
            self.notice_var.set("请先取消或完成本轮校准，再读取配置。")
            return
        path = filedialog.askopenfilename(parent=self.root, title="读取校准配置", filetypes=[("校准配置", "*.json")])
        if path:
            try:
                candidate = Profile.load(path)
                candidate.save(self.profile_path)
                self.model.set_profile(candidate)
                self.update_profile_label()
                self.notice_var.set(f"已加载：{Path(path).name}。请核对当前装配是否与配置一致。")
                self.need_sync = True
            except (OSError, ValueError, TypeError) as exc:
                self.notice_var.set(f"配置未加载，原配置保留：{exc}")

    def selected_effect(self):
        return EFFECTS.index(self.effect_var.get()), ['从左到右', '从上到下'].index(self.direction_var.get())

    def game_mode(self):
        return bool(self.board and self.board.last_status and self.board.last_status.mode==5)

    def start_game(self,game):
        now=time.monotonic()
        if not self.board or not self.game_status or now-self.game_updated>.6:
            self.notice_var.set('请连接新版游戏固件，等待有效板上游戏状态。');return
        if self.board.busy or self.need_sync or self.auto_sync_pending or self.model.session or not self.board.last_status or not self.board.last_status.configured:
            self.notice_var.set('请先完成32键校准下发，等待板卡确认后开始。');return
        self.board.start([dict(code=GAME_START,key=game)],'开始游戏')
        self.notice_var.set('开始命令已排队；倒计时、规则和计分均由FPGA运行。')

    def stop_game(self):
        if self.board and not self.board.busy and self.game_mode():
            mode,direction=self.selected_effect()
            self.board.start([dict(code=GAME_STOP,mode=mode,direction=direction)],'结束游戏')
            self.notice_var.set('结束命令已排队，确认后恢复所选普通灯效。')

    def request_sync(self):
        if self.game_mode():
            self.notice_var.set('请先结束游戏，再重发校准。');return
        if not self.board or not self.board.supported:
            self.notice_var.set('尚未确认板卡支持配置协议，请连接新版键盘灯效固件。')
            return
        self.need_sync = True

    def send_effect(self):
        try:
            if not self.board or not self.board.supported or self.input_kind != 'live':
                raise ValueError('请先连接支持配置协议的板卡')
            mode, direction = self.selected_effect()
            if self.board.busy:
                raise ValueError('正在等待板卡确认，请稍候')
            self.effect_settings = dict(mode=mode, direction=direction)
            target = self.state_dir / 'effects.json'
            temp = target.with_suffix('.tmp')
            temp.write_text(json.dumps(self.effect_settings), encoding='utf-8')
            os.replace(temp, target)
            self.board.start([dict(code=EFFECT, mode=mode, direction=direction)], '灯效切换')
            self.notice_var.set('灯效命令已排队，以下方板卡应答为准。方向选择仅用于快速整板流水。')
        except (ValueError, OSError, queue.Full) as exc:
            self.notice_var.set(f'灯效未下发：{exc}')

    def poll_board(self, now):
        board = self.board
        if board is None or not self.input_ready:
            self.board_label.configure(text='未连接实时板卡' if self.input_kind != 'replay' else '历史回放 · 禁止下发配置')
            self.effect_button.configure(state='disabled')
            self.sync_button.configure(state='disabled')
            return
        if board.supported and self.auto_sync_pending:
            self.auto_sync_pending = False
            if self.game_mode() and board.last_status.configured:
                self.need_sync = False
                self.notice_var.set('已恢复板上游戏状态；保持当前对局与板上校准。')
            else:
                self.need_sync = True
        try:
            if self.need_sync and board.supported and not board.busy and not self.model.session and not self.game_mode():
                self.need_sync = False
                mode, direction = self.selected_effect()
                plan = calibration_commands(self.model.profile) + [dict(code=EFFECT, mode=mode, direction=direction)]
                board.start(plan, '校准、阈值与灯效下发')
            board.tick(now)
        except (ValueError, OSError, queue.Full) as exc:
            board.message = f'发送失败：{exc}'
            board.queue.clear(); board.pending = None
            board.failures += 1
        enabled = board.supported and not board.busy
        self.effect_button.configure(state='normal' if enabled else 'disabled')
        self.sync_button.configure(state='normal' if enabled else 'disabled')
        state = board.last_status
        suffix = ''
        if state:
            effect_name='5 · 板上小游戏' if state.mode==5 else EFFECTS[state.mode]
            suffix = f'\nFPGA：{effect_name}\n' + (f'配置已生效 #{state.generation}' if state.configured else '等待完整校准配置')
            if now - board.updated > .6:
                suffix += ' · 应答超时'
        self.board_label.configure(text=board.message + suffix, fg=GREEN if state and state.configured and not board.busy and now-board.updated<.6 else AMBER)

    def toggle_recording(self):
        if self.record_file:
            self.stop_recording()
            self.notice_var.set("CSV记录已保存。")
            return
        if not self.reader or not self.input_ready:
            self.notice_var.set("先连接串口或打开回放，再录制数据。")
            return
        path = filedialog.asksaveasfilename(parent=self.root, title="录制原始值和软件按键状态", defaultextension=".csv", initialfile="keyboard_" + datetime.now().strftime("%Y%m%d_%H%M%S") + ".csv", filetypes=[("CSV数据", "*.csv")])
        if path:
            try:
                self.record_file = open(path, "w", newline="", encoding="utf-8-sig")
                self.csv_writer = csv.writer(self.record_file)
                self.csv_writer.writerow(["elapsed_s", "key", "raw_adc", "depth_percent", "pressed", "source"])
                self.record_start = time.monotonic()
                self.record_button.configure(text="停止录制")
                self.notice_var.set("正在录制：" + Path(path).name)
            except OSError as exc:
                self.stop_recording()
                self.notice_var.set(f"录制失败：{exc}")

    def stop_recording(self):
        handle = self.record_file
        self.record_file = self.csv_writer = None
        self.record_button.configure(text="录制 CSV")
        if handle:
            handle.close()

    def draw_chart(self, now):
        canvas = self.chart
        canvas.delete("all")
        width, height = canvas.winfo_width(), canvas.winfo_height()
        left, right, top, bottom = 46, width - 18, 12, height - 25
        data = [(t, v) for t, v in self.model.histories[self.selected] if now - t <= 12]
        cal = self.model.profile.keys[self.selected]
        vals = [v for _, v in data] + ([cal.rest, cal.bottom] if cal else [])
        low = max(0, min(vals) - 80) if vals else 0
        high = min(4095, max(vals) + 80) if vals else 4095
        high = max(high, low + 100)
        def yy(v):
            return bottom - (v - low) / (high - low) * (bottom - top)
        for fraction in [0, .5, 1]:
            v = low + (high - low) * fraction
            y = yy(v)
            canvas.create_line(left, y, right, y, fill=LINE)
            canvas.create_text(left - 8, y, text=f"{v:.0f}", fill=MUTED, anchor="e", font=(FONT, 8))
        if cal:
            for value, color in [(cal.rest, MUTED), (cal.bottom, AMBER)]:
                canvas.create_line(left, yy(value), right, yy(value), fill=color, dash=(4, 4))
        points = []
        for t, value in data:
            points.extend((right - (now - t) / 12 * (right - left), yy(value)))
        if len(points) >= 4:
            canvas.create_line(*points, fill=CYAN, width=2)
        canvas.create_text(left, height - 10, text="原始 ADC · 最近12秒", anchor="w", fill=MUTED, font=(FONT, 8))
        canvas.create_text(right, height - 10, text="虚线：松开 / 到底", anchor="e", fill=MUTED, font=(FONT, 8))

    def _poll(self):
        if not self.reader:
            return
        ended = False
        while True:
            try:
                state, message = self.reader.status.get_nowait()
            except queue.Empty:
                break
            if state == "ready":
                self.input_ready = True
                if self.board:
                    self.board.start([dict(code=QUERY)], '查询板卡协议')
                self.notice_var.set("实时串口已打开，等待有效键盘数据。" if self.input_kind == "live" else "正在回放历史数据；不代表当前硬件状态，回放不能做实时校准。")
            elif state in ("error", "eof"):
                self.notice_var.set(("串口异常：" if state == "error" else "") + message)
            elif state == "warmup":
                self.notice_var.set(message)
            elif state == "closed":
                ended = True
        for _ in range(128):
            try:
                timestamp, data = self.reader.data.get_nowait()
            except queue.Empty:
                break
            previous_errors = self.parser.sequence_errors
            samples = self.parser.feed(data)
            if self.parser.sequence_errors > previous_errors and self.model.session:
                self.model.session.abort("扫描序列中断，候选校准取消；原配置保留")
            for key, raw in samples:
                depth = self.model.update(key, raw, timestamp)
                if self.csv_writer:
                    try:
                        self.csv_writer.writerow([f"{timestamp - self.record_start:.4f}", key, raw,
                                                  "" if depth is None else f"{depth * 100:.3f}", int(self.model.pressed[key - 1]), self.input_kind])
                    except OSError as exc:
                        self.stop_recording()
                        self.notice_var.set(f"CSV写入失败：{exc}")
            while self.parser.statuses:
                board_status = self.parser.statuses.popleft()
                if self.board:
                    was_configured = self.board.last_status and self.board.last_status.configured
                    self.board.receive(board_status, timestamp)
                    self.model.apply_board_state(board_status, timestamp)
                    if was_configured and not board_status.configured:
                        self.need_sync = True
            while self.parser.game_statuses:
                self.game_status=self.parser.game_statuses.popleft()
                self.game_updated=timestamp
        if self.reader.dropped != self.queue_dropped:
            self.queue_dropped = self.reader.dropped
            if self.model.session:
                self.model.session.abort("接收队列发生丢弃，候选校准取消")
        if ended:
            self.disconnect(quiet=True)

    def tick(self):
        if self.closing:
            return
        # Schedule before work so a recoverable callback error cannot silently stop updates.
        self.root.after(33, self.tick)
        self._poll()
        now = time.monotonic()
        self.poll_board(now)
        game_fresh=self.input_kind=='live' and now-self.game_updated<.6
        game_ready=bool(game_fresh and self.board and self.board.last_status and self.board.last_status.configured and not self.board.busy and not self.need_sync and not self.auto_sync_pending and not self.model.session)
        game_message=self.board.message if self.board and self.board.busy else ''
        self.games_page.refresh(self.game_status,game_fresh,game_ready,bool(game_fresh and self.board and not self.board.busy and self.game_mode()),game_message)
        self.model.tick(now)
        fresh = sum(self.model.fresh(i, now) for i in range(32))
        if fresh == 32 and self.input_kind == "live" and self.notice_var.get() == "实时串口已打开，等待有效键盘数据。":
            self.notice_var.set("实时数据已就绪。可直接观察按键，或按1 → 2 → 3重新校准。")
        if now - self.last_rate >= 1:
            elapsed = now - self.last_rate
            self.rate_records = (self.parser.records - self.previous_records) / elapsed
            self.rate_scans = (self.parser.scans - self.previous_scans) / elapsed
            self.previous_records, self.previous_scans = self.parser.records, self.parser.scans
            self.last_rate = now
            if self.record_file:
                try:
                    self.record_file.flush()
                except OSError as exc:
                    self.stop_recording()
                    self.notice_var.set(f"CSV写入失败，录制已停止：{exc}")
        label = "实时" if self.input_kind == "live" else "历史回放" if self.input_kind == "replay" else "未连接"
        if self.reader and fresh == 0:
            label += " · 等待数据"
        self.connection_label.configure(text="● " + label, fg=GREEN if fresh == 32 and self.input_kind == "live" else AMBER if self.reader else MUTED)
        self.matrix.refresh(self.model, self.selected, now)
        i = self.selected
        self.detail_title.configure(text=f"K{i + 1:02d} / 第{i // 8 + 1}行 · 第{i % 8 + 1}列")
        cal, raw, depth = self.model.profile.keys[i], self.model.raw[i], self.model.depth(i, now)
        detail = f"ADC {raw if raw is not None else '—'}   ·   " + (f"深度 {depth * 100:.1f}%" if depth is not None else "未校准 / 数据待更新")
        if cal:
            detail += f"   ·   松开 {cal.rest:g}   到底 {cal.bottom:g}   行程 {abs(cal.bottom - cal.rest):g}"
        self.detail_text.configure(text=detail)
        targets = [self.selected] if self.scope_var.get() == "仅选中键" else range(32)
        live = self.input_kind == "live" and self.input_ready and all(self.model.fresh(k, now) for k in targets)
        self.rest_button.configure(state="normal" if live and not self.game_mode() else "disabled")
        session = self.model.session
        self.bottom_button.configure(state="normal" if live and session and session.stage == "ready" else "disabled")
        self.apply_button.configure(state="normal" if live and session and session.complete else "disabled")
        self.cancel_button.configure(state="normal" if session else "disabled")
        if session:
            self.progress.configure(maximum=len(session.targets), value=len(session.bottom))
            if session.stage == "rest":
                text = f"采集中：请松开全部目标按键\n剩余 {max(0, 2 - (now - session.started)):.1f}秒"
            elif session.stage == "ready":
                text = "松开位置已采集。\n点击第2步，逐键按到底并保持0.3秒。"
            elif session.stage == "press":
                text = f"有效终点 {len(session.bottom)}/{len(session.targets)}\n" + ("已齐全，可以应用校准。" if session.complete else "逐键按到底；完成的键显示 ✓。")
            else:
                text = session.error
            self.cal_label.configure(text=text, fg=AMBER if session.stage == "error" else MUTED)
        else:
            self.progress.configure(maximum=32, value=0)
            self.cal_label.configure(text="全部松开按键，再采集零点。\n随后逐键按到底，完成后应用。", fg=MUTED)
        if now - self.last_graph >= .1:
            self.draw_chart(now)
            self.last_graph = now
            events = list(self.model.events)[-8:]
            self.events_label.configure(text="最近事件  " + "   ".join(f"K{k:02d} {'按下' if p else '松开'}" for _, k, p in events) if events else "按键事件会显示在这里")
        self.stats_var.set(f"{label} · {self.source_label}    新鲜数据 {fresh}/32    {self.rate_records:.0f} 条/秒 · {self.rate_scans:.1f} 轮/秒    累计 {self.parser.records:,}    序号异常 {self.parser.sequence_errors} · 丢弃字节 {self.parser.discarded + self.queue_dropped}" + ("    ● 正在录制" if self.record_file else ""))
        if self.args.diagnostics and now - self.last_diag >= 1:
            self.write_diagnostics(now)
            self.last_diag = now

    def write_diagnostics(self, now, retries=2):
        data = dict(source_kind=self.input_kind, source=self.source_label, input_ready=self.input_ready,
                    records=self.parser.records, scans=self.parser.scans, sequence_errors=self.parser.sequence_errors,
                    discarded_bytes=self.parser.discarded, queue_dropped=self.queue_dropped,
                    fresh_keys=sum(self.model.fresh(i, now) for i in range(32)),
                    raw=self.model.raw, depth=[self.model.depth(i, now) for i in range(32)], pressed=self.model.pressed,
                    profile=self.model.profile.name, calibrated_keys=sum(k is not None for k in self.model.profile.keys),
                    events=[dict(key=k, pressed=p) for _, k, p in self.model.events],
                    calibration_stage=self.model.session.stage if self.model.session else None,
                    calibration_covered=len(self.model.session.bottom) if self.model.session else 0,
                    serial_thread_alive=bool(self.reader and self.reader.thread.is_alive()))
        data['board'] = dict(supported=self.board.supported, busy=self.board.busy, message=self.board.message,
                             configured=bool(self.board.last_status and self.board.last_status.configured),
                             mode=self.board.last_status.mode if self.board.last_status else None,
                             direction=self.board.last_status.direction if self.board.last_status else None,
                             generation=self.board.last_status.generation if self.board.last_status else None,
                             pressed=self.board.last_status.pressed if self.board.last_status else None,
                             fresh=now-self.board.updated<.6, failures=self.board.failures,
                             completed=self.board.completed, total=self.board.total,
                             tx_bytes=self.reader.tx_bytes if self.reader else 0) if self.board else None
        path = self.args.diagnostics
        data['game'] = dict(**self.game_status.__dict__,fresh=now-self.game_updated<.6,source='FPGA') if self.game_status else None
        data['game_crc_errors'] = self.parser.game_errors
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(temporary, path)
        except PermissionError as exc:
            # Windows readers can briefly deny rename; retry without blocking Tk.
            if retries and not self.closing:
                self.root.after(35,lambda:self.write_diagnostics(time.monotonic(),retries-1))
            else:
                self.notice_var.set(f"诊断记录写入失败：{exc}")
        except OSError as exc:
            self.notice_var.set(f"诊断记录写入失败：{exc}")

    def callback_error(self, exc_type, exc, traceback):
        import traceback as tb
        with (self.state_dir / "errors.log").open("a", encoding="utf-8") as handle:
            tb.print_exception(exc_type, exc, traceback, file=handle)
        self.notice_var.set(f"程序错误：{exc}（日志已保存）")

    def close(self):
        self.closing = True
        try:
            self.disconnect(quiet=True)
        finally:
            if self.args.diagnostics:
                self.write_diagnostics(time.monotonic())
            self.root.destroy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port")
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--replay", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--diagnostics", type=Path)
    parser.add_argument("--quit-after", type=float)
    parser.add_argument("--games", action="store_true", help="Open the FPGA games page")
    args = parser.parse_args()
    if args.port and args.replay:
        parser.error("Choose either --port or --replay")
    root = tk.Tk()
    KeyboardApp(root, args)
    root.mainloop()


if __name__ == "__main__":
    main()
