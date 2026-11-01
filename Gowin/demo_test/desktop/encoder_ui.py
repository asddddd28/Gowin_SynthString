"""Five-channel monitor; all hardware counts originate in FPGA telemetry."""
import tkinter as tk
from tkinter import ttk

from encoder_core import PHYSICAL_ORDER, EDGES_PER_DETENT

BG, PANEL, CARD, LINE = '#0b1220', '#111d30', '#17263c', '#293b54'
TEXT, MUTED, CYAN, GREEN, AMBER = '#e4edf8', '#8da3bf', '#53d6d1', '#73e6a6', '#ffc473'
FONT = 'Microsoft YaHei UI'


class EncoderPanel(tk.Frame):
    def __init__(self, parent, zero):
        super().__init__(parent, bg=BG)
        self.canvas = tk.Canvas(self, bg=BG, highlightthickness=0)
        scroll = ttk.Scrollbar(self, orient='vertical', command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.canvas.pack(side='left', fill='both', expand=True)
        self.body = tk.Frame(self.canvas, bg=BG)
        window = self.canvas.create_window((0, 0), window=self.body, anchor='nw')
        self.body.bind('<Configure>', lambda event: self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.canvas.bind('<Configure>', lambda event: self.canvas.itemconfigure(window, width=event.width))
        def wheel(event):
            widget = self.winfo_containing(event.x_root, event.y_root)
            if widget is not None and str(widget).startswith(str(self)):
                self.canvas.yview_scroll(-int(event.delta / 120), 'units')
        self.winfo_toplevel().bind('<MouseWheel>', wheel, add='+')
        top = tk.Frame(self.body, bg=BG)
        top.pack(fill='x', pady=(18, 8))
        self.label(top, '五路编码器', 19).pack(side='left')
        self.zero_button = ttk.Button(top, text='显示位置归零', command=zero)
        self.zero_button.pack(side='right')
        self.message = self.label(self.body, '连接 DEBUG 串口，自动识别编码器固件。', 10, MUTED)
        self.message.pack(fill='x', pady=(0, 14))
        cards = tk.Frame(self.body, bg=BG)
        cards.pack(fill='x')
        self.cards = []
        for physical, channel in enumerate(PHYSICAL_ORDER, 1):
            col = physical - 1
            cards.columnconfigure(col, weight=1, uniform='encoder')
            card = tk.Frame(cards, bg=CARD, padx=10, pady=10, highlightthickness=1, highlightbackground=LINE)
            card.grid(row=0, column=col, sticky='nsew', padx=(0 if col == 0 else 8, 0))
            self.label(card, f'旋钮 {physical}    /    E{channel}', 13, CYAN, CARD).pack(fill='x')
            status = self.label(card, '等待数据', 10, MUTED, CARD)
            status.pack(fill='x', pady=(5, 5))
            value = self.label(card, '—', 26, TEXT, CARD)
            value.pack(fill='x')
            self.label(card, '相对位置 / 格', 9, MUTED, CARD).pack(fill='x', pady=(0, 8))
            phase = self.label(card, '原始  A —   B —\n滤波  A —   B —', 10, MUTED, CARD, justify='left')
            phase.pack(fill='x', pady=(0, 8))
            counters = self.label(card, 'FPGA Q   —\n正向 P    —\n反向 N    —\n非法 X    —', 10, MUTED, CARD, justify='left')
            counters.pack(fill='x')
            activity = self.label(card, '本次 +0 / −0\n非法 0 · 中断 0', 9, MUTED, CARD, justify='left')
            activity.pack(fill='x', pady=(8, 0))
            self.cards.append(dict(frame=card, status=status, value=value, phase=phase,
                                   counters=counters, activity=activity, channel=channel))
        self.label(self.body, '按实物从左到右排列 · 4 个边沿 = 1 格 · 顺时针为正\n'
                   '归零只改变 App 显示。超过 0.6 秒未更新会标为超时；A/B 是采样快照。',
                   10, MUTED, justify='left').pack(fill='x', pady=(13, 10))
        event_box = tk.Frame(self.body, bg=PANEL, padx=14, pady=10)
        event_box.pack(fill='both', expand=True, pady=(0, 8))
        self.label(event_box, '最近变化', 11, TEXT, PANEL).pack(anchor='w')
        self.events = self.label(event_box, '转动任一旋钮即可观察响应。', 10, MUTED, PANEL, justify='left')
        self.events.pack(fill='x', pady=(6, 0))

    @staticmethod
    def label(parent, text, size=10, color=TEXT, bg=BG, **kwargs):
        return tk.Label(parent, text=text, bg=bg, fg=color, font=(FONT, size), anchor='w', **kwargs)

    def refresh(self, model, now, source, protocol):
        count = sum(c.fresh(now) for c in model.channels)
        if protocol == 'keyboard':
            message = '当前是键盘固件。查看编码器需要加载 EncoderDebug 固件后重新连接。'
        elif source == 'none':
            message = '未连接 · 保留最后计数；连接 DEBUG 串口后自动识别。'
        elif source == 'replay':
            message = f'历史回放 · {count}/5 路数据更新 · 不是当前硬件状态'
        elif protocol in ('encoder','hub'):
            message = f'实时串口 · {count}/5 路数据更新 · 编码器状态由 FPGA 回传'
        else:
            message = '等待有效数据 · 请连接运行 EncoderDebug 固件的 DEBUG 串口。'
        self.message.configure(text=message, fg=GREEN if count == 5 and source == 'live' else AMBER)
        self.zero_button.configure(state='normal' if count else 'disabled')
        for card in self.cards:
            c = model.channels[card['channel'] - 1]
            fresh, record = c.fresh(now), c.record
            moving = fresh and c.direction(now) != '静止'
            color = CYAN if moving else GREEN if fresh else MUTED
            card['frame'].configure(highlightbackground=color if fresh else LINE)
            card['status'].configure(text=c.direction(now), fg=color)
            value = f'{c.edges / EDGES_PER_DETENT:+.6g}' if record else '—'
            card['value'].configure(text=value, font=(FONT, 26 if len(value) <= 6 else 19), fg=TEXT if fresh else MUTED)
            if record:
                card['phase'].configure(text=f'原始  A {record.raw >> 1}   B {record.raw & 1}\n'
                                             f'滤波  A {record.filtered >> 1}   B {record.filtered & 1}')
                card['counters'].configure(text=f'FPGA Q   {record.q:+d}\n正向 P    {record.positive}\n'
                                                f'反向 N    {record.negative}\n非法 X    {record.invalid}')
            else:
                card['phase'].configure(text='原始  A —   B —\n滤波  A —   B —')
                card['counters'].configure(text='FPGA Q   —\n正向 P    —\n反向 N    —\n非法 X    —')
            card['activity'].configure(text=f'本次 +{c.positive} / −{c.negative}\n非法 {c.invalid} · 中断 {c.discontinuities}',
                                       fg=AMBER if c.invalid or c.discontinuities else MUTED)
        events = list(model.events)[-3:]
        self.events.configure(text='\n'.join(f'E{channel} · {text}' for _, channel, text in reversed(events))
                              if events else '转动任一旋钮即可观察响应。')
