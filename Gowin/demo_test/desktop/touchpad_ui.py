"""左右拼接触摸面、两组电极条及原始寄存器读数。"""
import tkinter as tk
import math
from tkinter import ttk
from touchpad_core import ERRORS, TouchpadMapping
from guitar_core import NOTE_NAMES, STRING_X, STRING_Y, display_point

BG, CARD, LINE = '#0b1220', '#17263c', '#293b54'
TEXT, MUTED, CYAN, GREEN, AMBER = '#e4edf8', '#8da3bf', '#53d6d1', '#73e6a6', '#ffc473'
FONT = 'Microsoft YaHei UI'

# 用户 PCB 标注：两块等宽板，感应区跨距含中间无感应间隙。
PAD_WIDTH_MM, PAD_HEIGHT_MM = 43.596, 61.976
PCB_WIDTH_MM, PCB_HEIGHT_MM = 46.609, 66.929
ACTIVE_SPAN_MM = 90.832
PAD_GAP_MM = ACTIVE_SPAN_MM - 2 * PAD_WIDTH_MM
SIDE_MARGIN_MM = (2 * PCB_WIDTH_MM - ACTIVE_SPAN_MM) / 2
VERTICAL_MARGIN_MM = (PCB_HEIGHT_MM - PAD_HEIGHT_MM) / 2


def pcb_layout(width, height):
    # X、Y 共用一个缩放系数，窗口改变时保持毫米比例，不拉伸触摸面。
    scale = max(.01, min((width-88)/(2*PCB_WIDTH_MM), (height-112)/PCB_HEIGHT_MM))
    left = (width-2*PCB_WIDTH_MM*scale)/2 - 8
    top = 32 + max(0, (height-112-PCB_HEIGHT_MM*scale)/2)
    boxes = []
    for side in range(2):
        x = left + (SIDE_MARGIN_MM + side*(PAD_WIDTH_MM+PAD_GAP_MM))*scale
        y = top + VERTICAL_MARGIN_MM*scale
        boxes.append((x, y, x+PAD_WIDTH_MM*scale, y+PAD_HEIGHT_MM*scale))
    return scale, left, top, boxes


class TouchpadPanel(ttk.Frame):
    def __init__(self, parent, mapping=None, on_mapping=None, on_guitar=None, on_panic=None):
        super().__init__(parent)
        mapping = mapping or TouchpadMapping()
        self.on_mapping = on_mapping
        self.on_guitar = on_guitar
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)
        header = ttk.Frame(self)
        header.grid(row=0, column=0, sticky='ew', padx=20, pady=(16, 4))
        self.title = ttk.Label(header, text='双触摸板 · 六弦吉他', font=(FONT, 17, 'bold'))
        self.title.pack(side='left')
        self.guitar_enabled = tk.BooleanVar(value=True)
        self.volume = tk.DoubleVar(value=30)
        ttk.Button(header, text='止音', command=on_panic).pack(side='right', padx=(12, 0))
        ttk.Scale(header, from_=0, to=100, variable=self.volume, command=self.guitar_changed, length=100).pack(side='right')
        ttk.Label(header, text='音量', style='Muted.TLabel').pack(side='right', padx=8)
        ttk.Checkbutton(header, text='吉他模式', variable=self.guitar_enabled, command=self.guitar_changed,
                        style='Touchpad.TCheckbutton').pack(side='right', padx=16)
        self.subtitle = ttk.Label(self, text='等待 FPGA 触摸板固件 · 单指位置估算 / 12 路电极 × 2')
        self.subtitle.grid(row=1, column=0, sticky='w', padx=20, pady=(0, 8))
        body = ttk.Frame(self)
        body.grid(row=2, column=0, sticky='nsew', padx=18)
        body.columnconfigure(0, weight=1)
        body.columnconfigure(1, weight=0, minsize=360)
        body.rowconfigure(0, weight=1)
        self.surface = tk.Canvas(body, bg=BG, highlightthickness=0, width=600, height=430)
        self.surface.grid(row=0, column=0, sticky='nsew', padx=(0, 16))
        options = ttk.Frame(self)
        options.grid(row=3, column=0, sticky='ew', padx=20, pady=7)
        self.swap = tk.BooleanVar(value=mapping.swap_boards)
        self.transpose = tk.BooleanVar(value=mapping.transpose)
        self.flip_x = tk.BooleanVar(value=mapping.flip_x)
        self.flip_y = tk.BooleanVar(value=mapping.flip_y)
        for text, var in [('两板对角线镜像 ↘', self.transpose), ('交换左右板', self.swap), ('每块板左右翻转', self.flip_x), ('上下翻转', self.flip_y)]:
            ttk.Checkbutton(options, text=text, variable=var, command=self.mapping_changed).pack(side='left', padx=(0, 18))
        ttk.Label(options, text='仅改变显示方向').pack(side='right')
        detail = ttk.Frame(body)
        detail.grid(row=0, column=1, sticky='nsew', pady=(4, 8))
        detail.columnconfigure(0, weight=1)
        detail.rowconfigure((0, 1), weight=1, uniform='touchpad_details')
        style = ttk.Style(self)
        style.configure('Touchpad.Treeview', background=CARD, fieldbackground=CARD, foreground=TEXT,
                        bordercolor=LINE, lightcolor=LINE, darkcolor=LINE, font=(FONT, 9), rowheight=24)
        style.configure('Touchpad.Treeview.Heading', background=LINE, foreground=TEXT,
                        font=(FONT, 9), relief='flat')
        style.map('Touchpad.Treeview', background=[('selected', '#294961')], foreground=[('selected', TEXT)])
        style.configure('Touchpad.TCheckbutton', background=BG, foreground=TEXT)
        for child in options.winfo_children():
            if isinstance(child, ttk.Checkbutton):
                child.configure(style='Touchpad.TCheckbutton')
        self.labels, self.tables = [], []
        for side in range(2):
            frame = ttk.Frame(detail)
            frame.grid(row=side, column=0, sticky='nsew', pady=(0, 12) if side == 0 else (0, 0))
            label = ttk.Label(frame, text=f'TOUCHPAD {side+1} · 等待数据', font=(FONT, 9))
            label.pack(anchor='w', pady=(0, 4))
            table = ttk.Treeview(frame, columns=('name', 'filtered', 'base', 'delta', 'touch'),
                                 show='headings', height=4, style='Touchpad.Treeview')
            for col, title, width in [('name','电极',76),('filtered','滤波值',70),('base','基线',66),('delta','差值',62),('touch','触摸',54)]:
                table.heading(col, text=title)
                table.column(col, width=width, anchor='center')
            table.tag_configure('touch', foreground=GREEN)
            for i in range(12):
                table.insert('', 'end', iid=str(i), values=(f'E{i:02d} '+('行' if i<5 else '列'), '—','—','—','—'))
            scroll = ttk.Scrollbar(frame, orient='vertical', command=table.yview)
            table.configure(yscrollcommand=scroll.set)
            scroll.pack(side='right', fill='y')
            table.pack(fill='both', expand=True)
            self.labels.append(label)
            self.tables.append(table)
        self.last_draw = float('-inf')
        self.audio_label = ttk.Label(self, text='横向划过竖弦发声 · 初次触摸与停留不拨弦', style='Muted.TLabel')
        self.audio_label.grid(row=4, column=0, sticky='w', padx=20, pady=(0, 6))

    def guitar_changed(self, *_):
        if self.on_guitar:
            self.on_guitar(self.guitar_enabled.get(), self.volume.get()/100)
        self.last_draw = float('-inf')

    def mapping(self):
        return TouchpadMapping(self.swap.get(), self.transpose.get(), self.flip_x.get(), self.flip_y.get())

    def mapping_changed(self):
        self.last_draw = float('-inf')
        if self.on_mapping:
            self.on_mapping(self.mapping())

    def refresh(self, state, now, source, protocol, guitar=None, audio=None):
        if now-self.last_draw < .05:
            return
        self.last_draw = now
        mapping = self.mapping()
        guitar_mode = self.guitar_enabled.get()
        self.title.configure(text='双触摸板 · 六弦吉他' if guitar_mode else '双触摸板 · 左右拼接')
        self.subtitle.configure(text=('历史回放 · ' if source=='replay' else '') +
            ('左 E2 · A2 · D3   /   右 G3 · B3 · E4  ·  横向划弦，声音自然衰减' if guitar_mode else
             '感应区 43.596 × 61.976 mm / 块 · 按 PCB 比例显示 · 单指位置估算'
             if protocol in ('touchpad','hub') else '感应区 43.596 × 61.976 mm / 块 · 等待 FPGA 触摸板固件'))
        if guitar_mode and guitar is not None and audio is not None:
            latest = guitar.events[-1] if guitar.events else None
            recent = f' · 最近 {NOTE_NAMES[latest.string]} {"→" if latest.direction>0 else "←"}' if latest else ''
            status = audio.status if source=='live' else '等待实时连接，回放不发声'
            if source=='live' and hasattr(guitar,'records'):
                if any(guitar.records):
                    rates=' / '.join(f'{rate:.0f}' for rate in guitar.rates)
                    status=f'FPGA 划弦 · 采样 {rates} Hz · {audio.status}'
                else: status='等待 FPGA 划弦固件 G1 · 当前不由软件判弦'
            self.audio_label.configure(text=f'{status} · 已拨弦 {sum(guitar.counts)} 次{recent}',
                                       foreground=AMBER if audio.error else MUTED)
        else:
            self.audio_label.configure(text='吉他模式已关闭' if not guitar_mode else '等待实时触摸板', foreground=MUTED)
        c = self.surface
        c.delete('all')
        width, height = c.winfo_width(), c.winfo_height()
        scale, left, top, boxes = pcb_layout(width, height)
        outer_right = left + 2*PCB_WIDTH_MM*scale
        outer_bottom = top + PCB_HEIGHT_MM*scale
        c.create_rectangle(left,top,outer_right,outer_bottom,fill='#111d30',outline=LINE,width=2)
        seam = left+PCB_WIDTH_MM*scale
        c.create_line(seam,top,seam,outer_bottom,fill=LINE,dash=(3,4))
        dimension_y = outer_bottom+14
        c.create_line(boxes[0][0],dimension_y,boxes[1][2],dimension_y,fill=MUTED,arrow='both')
        c.create_text((boxes[0][0]+boxes[1][2])/2,dimension_y+13,text='90.832 mm · 总感应跨距',fill=MUTED,font=(FONT,9))
        dimension_x = outer_right+18
        c.create_line(dimension_x,boxes[0][1],dimension_x,boxes[0][3],fill=MUTED,arrow='both')
        c.create_text(dimension_x+15,(boxes[0][1]+boxes[0][3])/2,text='61.976 mm',fill=MUTED,font=(FONT,9),angle=90)
        for endpoint in (boxes[0][0],boxes[1][2]):
            c.create_line(endpoint,outer_bottom+6,endpoint,dimension_y+5,fill=LINE)
        for board in range(2):
            pos = 1-board if mapping.swap_boards else board
            x0,y0,x1,y1 = boxes[pos]
            r = state.records[board]
            fresh = state.fresh(board, now)
            color = CYAN if board==0 else '#a69aff'
            c.create_rectangle(x0,y0,x1,y1,fill=CARD,outline=color if fresh else LINE,width=2,tags=(f'pad{board+1}',))
            c.create_text((x0+x1)/2,top-17,text=f'TP{board+1} · {"左" if pos==0 else "右"} · 43.596 mm',fill=color,font=(FONT,10,'bold'))
            for row in range(5):
                ax, ay = mapping.apply(.01, (row+.5)/5)
                bx, by = mapping.apply(.99, (row+.5)/5)
                active=fresh and bool(r.mask & 1<<row)
                c.create_line(x0+ax*(x1-x0),y0+ay*(y1-y0),x0+bx*(x1-x0),y0+by*(y1-y0),fill=color if active and not guitar_mode else LINE,width=3 if active and not guitar_mode else 1)
            for col in range(7):
                ax, ay = mapping.apply((col+.5)/7, .01)
                bx, by = mapping.apply((col+.5)/7, .99)
                active=fresh and bool(r.mask & 1<<(col+5))
                c.create_line(x0+ax*(x1-x0),y0+ay*(y1-y0),x0+bx*(x1-x0),y0+by*(y1-y0),fill=color if active and not guitar_mode else LINE,width=3 if active and not guitar_mode else 1)
            if guitar_mode:
                for slot, sx in enumerate(STRING_X):
                    string = pos*3+slot
                    elapsed = now-guitar.last_hits[string] if guitar else 100
                    ringing = 0 <= elapsed < .65
                    x = x0+sx*(x1-x0)
                    sy0, sy1 = y0+STRING_Y[0]*(y1-y0), y0+STRING_Y[1]*(y1-y0)
                    wobble = math.sin(elapsed*65)*4*(1-elapsed/.65) if ringing else 0
                    string_color = AMBER if ringing else '#d5bc8e' if string<3 else '#cdd9ea'
                    c.create_line(x,sy0,x+wobble,(sy0+sy1)/2,x,sy1,fill=string_color,
                                  width=1.2+(5-string)*.30,smooth=True,tags=(f'guitar_string{string}',))
                    c.create_text(x,y0+7,text=f'{6-string} {NOTE_NAMES[string]}',fill=string_color,font=(FONT,9,'bold'))
            point=state.position(board,now)
            if point:
                px,py=display_point(point,mapping)
                x=x0+px*(x1-x0)
                y=y0+py*(y1-y0)
                c.create_oval(x-18,y-18,x+18,y+18,outline=color,width=2)
                c.create_oval(x-6,y-6,x+6,y+6,fill=color,outline='')
            label='未触摸' if fresh and not r.mask else '检测到电极变化' if fresh else '等待有效采样'
            if fresh and r.fault: label='电极超范围 / 自动配置异常'
            if fresh and not any(r.filtered): label='采样全零 · 待排查'
            if point:
                px,py=mapping.apply(*point)
                label=f'X {px*100:.0f}%   ·   Y {py*100:.0f}%'
            c.create_text((x0+x1)/2,outer_bottom+55,text=label,fill=MUTED,font=(FONT,9),width=max(80,x1-x0),justify='center')
            status=ERRORS.get(r.error,'未知状态') if r else '等待数据'
            if r and now-state.received[board]>.6: status='串口数据超时'
            elif r and r.error==0 and not fresh: status='采样计数停止'
            if r and fresh and r.fault: status='电极超范围 / 配置异常'
            if r and fresh and not any(r.filtered): status='通信正常，采样全零'
            self.labels[board].configure(text=f'TOUCHPAD {board+1} · {status}'+(f'\n0x{r.address:02X}   IRQ {r.lines&1} · SCL {(r.lines>>1)&1} · SDA {(r.lines>>2)&1}' if r else '\n等待串口数据'))
            for i in range(12):
                axis = '列' if (i<5) == mapping.transpose else '行'
                self.tables[board].item(str(i),values=(f'E{i:02d} '+axis,
                    r.filtered[i] if fresh else '—', r.baseline[i] if fresh else '—',r.delta[i] if fresh else '—',
                    '●' if fresh and r.mask & 1<<i else ''),tags=('touch',) if fresh and r.mask & 1<<i else ())
