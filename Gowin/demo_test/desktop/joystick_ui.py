"""摇杆造型的只读状态显示，原始电平与显示映射相互独立。"""
import math
import tkinter as tk
from tkinter import ttk

from joystick_core import NAMES, JoystickMapping

BG, PANEL, CARD, LINE = '#0b1220', '#111d30', '#17263c', '#293b54'
TEXT, MUTED, CYAN, GREEN, AMBER = '#e4edf8', '#8da3bf', '#53d6d1', '#73e6a6', '#ffc473'
FONT = 'Microsoft YaHei UI'


def mix(first, second, amount):
    a = tuple(int(first[n:n + 2], 16) for n in (1, 3, 5))
    b = tuple(int(second[n:n + 2], 16) for n in (1, 3, 5))
    return '#' + ''.join(f'{round(x + (y - x) * amount):02x}' for x, y in zip(a, b))


class JoystickView(tk.Canvas):
    """固定底座和倾斜杆头；九个离散目标之间的过渡只用于视觉。"""
    def __init__(self, parent):
        super().__init__(parent, bg=PANEL, highlightthickness=0)
        self.shown = (0.0, 0.0)
        self.target = (0, 0)
        self.last_time = None
        self.last_size = None
        self.render_key = None
        self.valid = False
        self.pressed = False
        self.direction = '等待数据'

    def backdrop(self, width, height):
        self.delete('all')
        self.cx, self.cy = width * .5, height * .51
        self.radius = max(36, min(width * .32, (height - 46) * .35))
        cx, cy, r = self.cx, self.cy, self.radius
        # 底座投影、斜边与同心槽均为原生矢量图形。
        self.create_oval(cx - r * 1.08, cy - r * .62, cx + r * 1.08, cy + r * 1.22,
                         fill='#09101c', outline='')
        self.create_oval(cx - r, cy - r + 10, cx + r, cy + r + 10, fill='#091320', outline='#24384e', width=2)
        for step in range(14):
            rad = r * (1 - step * .009)
            self.create_oval(cx - rad, cy - rad, cx + rad, cy + rad,
                             fill=mix('#344a60', '#15253a', step / 13), outline='')
        self.create_oval(cx - r * .84, cy - r * .84, cx + r * .84, cy + r * .84,
                         fill='#0c1829', outline='#41536a', width=2)
        self.create_oval(cx - r * .78, cy - r * .78, cx + r * .78, cy + r * .78,
                         fill='#102035', outline='#1c354a', width=2)
        for axis in (-1, 1):
            self.create_line(cx + axis * r * .27, cy, cx + axis * r * .68, cy, fill='#2a3e52', dash=(2, 5))
            self.create_line(cx, cy + axis * r * .27, cx, cy + axis * r * .68, fill='#2a3e52', dash=(2, 5))
        for angle in range(0, 360, 45):
            a = math.radians(angle)
            x, y = cx + math.cos(a) * r * .94, cy + math.sin(a) * r * .94
            self.create_oval(x - 3, y - 3, x + 3, y + 3, fill='#536579', outline='#111c2b')
        for dx, dy, text in ((0, -1, '上'), (1, 0, '右'), (0, 1, '下'), (-1, 0, '左')):
            self.create_text(cx + dx * r * 1.22, cy + dy * r * 1.22, text=text,
                             font=(FONT, 11), fill=MUTED, tags=f'cardinal_{text}')
        # 杆根嵌在底座的中心轴套内。
        self.create_oval(cx - r * .23, cy - r * .02, cx + r * .23, cy + r * .43,
                         fill='#070e18', outline='#3b5066', width=2)
        self.create_oval(cx - r * .15, cy + r * .04, cx + r * .15, cy + r * .34,
                         fill='#182a3b', outline='#2b4054')
        self.create_text(18, 18, text='JOYSTICK', anchor='w', font=(FONT, 9), fill='#58718d')
        self.create_text(width - 18, height - 18, text='九向状态 · 位置示意', anchor='e', font=(FONT, 9), fill='#6d849f')
        self.render_key = None

    def refresh(self, x, y, fresh, pressed, now):
        self.valid = fresh and x is not None and y is not None
        self.pressed = pressed and fresh
        self.direction = ('中心' if x == 0 and y == 0 else
                          ('左' if x == -1 else '右' if x == 1 else '') +
                          ('上' if y == 1 else '下' if y == -1 else '')) if self.valid else '组合异常' if fresh else '等待数据'
        self.target = (x, y) if self.valid else (0, 0)
        magnitude = math.hypot(*self.target)
        target = tuple(v / max(1, magnitude) for v in self.target)
        elapsed = min(.1, max(0, now - self.last_time)) if self.last_time is not None else .1
        alpha = 1 - math.exp(-elapsed / .055)
        self.shown = tuple(a + (b - a) * alpha for a, b in zip(self.shown, target)) if self.valid else (0, 0)
        self.shown = tuple(b if abs(a - b) < .002 else a for a, b in zip(self.shown, target))
        self.last_time = now
        size = (self.winfo_width(), self.winfo_height())
        if min(size) < 10:
            return
        if size != self.last_size:
            self.backdrop(*size)
            self.last_size = size
        key = (tuple(round(v, 3) for v in self.shown), self.valid, self.pressed, self.direction)
        if key == self.render_key:
            return
        self.render_key = key
        self.delete('moving')
        cx, cy, r = self.cx, self.cy, self.radius
        active = GREEN if self.pressed else CYAN
        if not self.valid:
            active = '#53677e'
        for direction in ('上', '右', '下', '左'):
            self.itemconfigure(f'cardinal_{direction}', fill=active if self.valid and direction in self.direction else MUTED)
        if self.valid and self.target != (0, 0):
            angle = math.degrees(math.atan2(self.target[1], self.target[0]))
            self.create_arc(cx - r * .88, cy - r * .88, cx + r * .88, cy + r * .88,
                            start=angle - 15, extent=30, style='arc', width=4, outline=active, tags='moving')
        px = cx + self.shown[0] * r * .46
        py = cy - self.shown[1] * r * .46 - r * (.16 if self.pressed else .25)
        cap = r * (.29 if self.pressed else .31)
        self.create_oval(px - cap * 1.05, py + cap * .1, px + cap * 1.05, py + cap * 1.4,
                         fill='#070f1c', outline='', tags='moving')
        for width, color, shift in ((.25, '#050b14', 0), (.18, '#42576a', 0), (.055, '#8299a8', -r * .035)):
            self.create_line(cx + shift, cy + r * .24, px + shift, py + cap * .3,
                             width=max(2, r * width), fill=color, capstyle='round', tags='moving')
        self.create_oval(px - cap, py - cap, px + cap, py + cap, fill='#081522', outline=active, width=2, tags='moving')
        # 偏左上的明暗层次形成球面；按压时变绿并略向下沉。
        for step in range(15):
            t = step / 14
            rad = cap * (.91 - t * .25)
            ox, oy = -cap * .12 * t, -cap * .14 * t
            self.create_oval(px + ox - rad, py + oy - rad, px + ox + rad, py + oy + rad,
                             fill=mix('#152b3e', mix(active, '#254158', .52), t), outline='', tags='moving')
        self.create_arc(px - cap * .72, py - cap * .75, px + cap * .65, py + cap * .62,
                        start=52, extent=75, style='arc', width=2, outline=mix(active, '#e4edf8', .35), tags='moving')
        self.create_oval(px - cap * .14, py - cap * .14, px + cap * .14, py + cap * .14,
                         fill=active if self.valid else '#7c8b9b', outline='', tags='moving')


class JoystickPanel(tk.Frame):
    def __init__(self, parent, mapping=None, on_change=None):
        super().__init__(parent, bg=BG)
        mapping = mapping or JoystickMapping()
        self.on_change = on_change
        header = tk.Frame(self, bg=BG)
        header.pack(fill='x', pady=(16, 4))
        self.label(header, '摇杆', 20).pack(side='left')
        self.label(header, '方向 / 按压', 10, MUTED).pack(side='left', padx=16, pady=(7, 0))
        self.message = self.label(header, '等待摇杆数据', 10, AMBER)
        self.message.pack(side='right')
        self.label(self, '移动实物摇杆，杆头会跟随方向；按下时亮绿。', 10, MUTED).pack(fill='x', pady=(0, 14))
        body = tk.Frame(self, bg=BG)
        body.pack(fill='both', expand=True)
        body.columnconfigure(0, weight=1)
        body.columnconfigure(1, minsize=300)
        body.rowconfigure(0, weight=1)
        self.pad = JoystickView(body)
        self.pad.grid(row=0, column=0, sticky='nsew', padx=(0, 16))
        side_area = tk.Frame(body, bg=CARD)
        side_area.grid(row=0, column=1, sticky='nsew')
        side_canvas = tk.Canvas(side_area, bg=CARD, highlightthickness=0, width=284)
        side_scroll = ttk.Scrollbar(side_area, orient='vertical', command=side_canvas.yview)
        side_canvas.configure(yscrollcommand=side_scroll.set)
        side_scroll.pack(side='right', fill='y')
        side_canvas.pack(side='left', fill='both', expand=True)
        side = tk.Frame(side_canvas, bg=CARD, padx=16, pady=14)
        side_window = side_canvas.create_window((0, 0), window=side, anchor='nw')
        side.bind('<Configure>', lambda event: side_canvas.configure(scrollregion=side_canvas.bbox('all')))
        side_canvas.bind('<Configure>', lambda event: side_canvas.itemconfigure(side_window, width=event.width))
        def scroll_side(event):
            widget = self.winfo_containing(event.x_root, event.y_root)
            if widget is not None and str(widget).startswith(str(side_area)):
                side_canvas.yview_scroll(-int(event.delta / 120), 'units')
        self.winfo_toplevel().bind('<MouseWheel>', scroll_side, add='+')
        self.label(side, '当前方向', 10, MUTED, CARD).pack(fill='x')
        self.direction = self.label(side, '—', 25, CYAN, CARD)
        self.direction.pack(fill='x', pady=(2, 10))
        self.button = self.label(side, '按压 SW · —', 13, TEXT, CARD)
        self.button.pack(fill='x', pady=(0, 5))
        self.count = self.label(side, '累计按下 — 次', 10, MUTED, CARD)
        self.count.pack(fill='x', pady=(0, 14))
        tk.Frame(side, bg=LINE, height=1).pack(fill='x', pady=(0, 12))
        table = tk.Frame(side, bg=CARD)
        table.pack(fill='x')
        for col, title in enumerate(('信号', '原始', '去抖')):
            table.columnconfigure(col, weight=1, uniform='signal')
            self.label(table, title, 9, MUTED, CARD).grid(row=0, column=col, sticky='w', pady=(0, 6))
        self.levels = []
        for bit, name in enumerate(NAMES):
            self.label(table, name, 10, MUTED, CARD).grid(row=bit + 1, column=0, sticky='w', pady=4)
            row = []
            for col in (1, 2):
                value = self.label(table, '—', 11, TEXT, CARD)
                value.grid(row=bit + 1, column=col, sticky='w', pady=4)
                row.append(value)
            self.levels.append(row)
        options = tk.Frame(self, bg=PANEL, padx=12, pady=8)
        options.pack(side='bottom', fill='x', pady=(12, 6))
        self.label(options, '显示方向', 10, MUTED, PANEL).pack(side='left', padx=(0, 16))
        self.swap = tk.BooleanVar(value=mapping.swap)
        self.flip_x = tk.BooleanVar(value=mapping.flip_x)
        self.flip_y = tk.BooleanVar(value=mapping.flip_y)
        for title, variable in [('交换 X/Y', self.swap), ('反转左右', self.flip_x), ('反转上下', self.flip_y)]:
            tk.Checkbutton(options, text=title, variable=variable, bg=PANEL, fg=TEXT,
                           selectcolor=CARD, activebackground=PANEL, activeforeground=CYAN,
                           command=self.mapping_changed).pack(side='left', padx=(0, 18))
        self.label(options, '自动保存', 9, MUTED, PANEL).pack(side='right')
        # 先保留底部设置条，再分配剩余高度给摇杆与可滚动状态栏。
        body.pack_forget()
        body.pack(fill='both', expand=True)

    @staticmethod
    def label(parent, text, size=10, color=TEXT, bg=BG, **kw):
        return tk.Label(parent, text=text, font=(FONT, size), fg=color, bg=bg, anchor='w', **kw)

    def mapping(self):
        return JoystickMapping(self.swap.get(), self.flip_x.get(), self.flip_y.get())

    def mapping_changed(self):
        if self.on_change:
            self.on_change(self.mapping())

    def refresh(self, model, now, source, protocol):
        state = model.snapshot(now)
        fresh, record = state['fresh'], model.record
        if protocol not in ('unknown', 'joystick','hub'):
            message = '当前固件无摇杆数据'
        elif source == 'none':
            message = '● 未连接'
        elif source == 'replay':
            message = '历史回放'
        else:
            message = '● 实时连接' if fresh else '● 等待数据'
        self.message.configure(text=message, fg=GREEN if fresh and source == 'live' else AMBER)
        x, y = self.mapping().apply(state['x'], state['y'])
        self.pad.refresh(x, y, fresh, state['pressed'], now)
        self.direction.configure(text=self.pad.direction if fresh else '—', fg=CYAN if self.pad.valid else AMBER)
        self.button.configure(text='按压 SW · ' + ('按下' if state['pressed'] else '松开') if fresh else '按压 SW · —',
                              fg=GREEN if state['pressed'] else TEXT)
        self.count.configure(text=f'FPGA 累计按下 {record.presses} 次' if record else '累计按下 — 次')
        for bit, row in enumerate(self.levels):
            for label, bits in zip(row, (record.raw, record.filtered) if record else (None, None)):
                value = (bits >> bit) & 1 if bits is not None else None
                label.configure(text=str(value) if value is not None else '—',
                                fg=CYAN if fresh and value else TEXT if fresh else MUTED)
