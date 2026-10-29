"""FPGA game dashboard. It contains no game engine, scoring or local key control."""
import tkinter as tk
from tkinter import ttk

BG='#0b1220';PANEL='#111d30';TEXT='#e4edf8';MUTED='#8da3bf';CYAN='#53d6d1'
COLORS=('#17263c','#48cf86','#ef6269','#53cddc')
FONT='Microsoft YaHei UI'
NAMES=('尚未选择','贪吃蛇','打地鼠','钢琴块')
CONTROLS={22:'↑',30:'↓',29:'←',31:'→'}
RULES=(
    '选择上方游戏开始。规则、倒计时、得分和灯光都由 FPGA 运行；关闭 App 后游戏继续。',
    '绿色是蛇，红色是苹果；青色四键为方向控制，不属于蛇的活动区域。\nK23 ↑　K31 ↓　K30 ←　K32 →　·　每个苹果 +10 分，撞墙或蛇身结束。',
    '60 秒内按下亮起的地鼠：绿色 +10，青色 +20，红色 +30。\n颜色不同，出现时间也不同；按空或漏按不扣分。每次需松开再按。',
    '上三行显示下一批方块，最底一行 K25–K32 是操作区，绿色是当前目标。\n按对后方块下移并 +1 分；按错、同时按多个底行键或超时，红闪并结束。')
REASONS=('时间到，结算完成','撞到边界或方向键区域','撞到蛇身','按错底行按键','未在限时内按下','已结束游戏','填满全部活动区域')


class GameMatrix(tk.Canvas):
    def __init__(self,parent):
        super().__init__(parent,bg=BG,highlightthickness=0,height=340)
        self.last_status=None
        self.bind('<Configure>',lambda event:self.render(self.last_status))

    def render(self,status):
        self.last_status=status
        self.delete('all')
        width=max(600,self.winfo_width());height=max(220,self.winfo_height())
        gap=10;left=28;top=22;cw=(width-left-12-7*gap)/8;ch=(height-top-12-3*gap)/4
        colors=status.colors if status else (0,)*32
        game=status.game if status else 0
        for key,color in enumerate(colors):
            row,col=divmod(key,8);x=left+col*(cw+gap);y=top+row*(ch+gap)
            border=CYAN if game==3 and row==3 else '#293b54'
            self.create_rectangle(x,y,x+cw,y+ch,fill=COLORS[color],outline=border,width=2)
            ink=BG if color else MUTED
            self.create_text(x+8,y+13,text=f'K{key+1:02d}',anchor='w',fill=ink,font=(FONT,9))
            label=CONTROLS.get(key,'') if game==1 else str(col+1) if game==3 and row==3 else ''
            if label:self.create_text(x+cw/2,y+ch*.62,text=label,fill=ink,font=(FONT,20,'bold'))
        self.create_text(left,10,text='板上游戏画面 · FPGA 状态回传',anchor='w',fill=MUTED,font=(FONT,9))


class GamesPanel(tk.Frame):
    def __init__(self,parent,start,stop):
        super().__init__(parent,bg=BG,padx=8,pady=8)
        self.last_render=None
        cards=tk.Frame(self,bg=BG);cards.pack(fill='x',pady=(0,14))
        self.buttons=[]
        for game,subtitle in ((1,'绿色蛇 · 红色苹果'),(2,'60 秒挑战 · 三色计分'),(3,'底行 8 键 · 越来越快')):
            cards.columnconfigure(game-1,weight=1)
            button=ttk.Button(cards,text=NAMES[game]+'\n'+subtitle,command=lambda chosen=game:start(chosen))
            button.grid(row=0,column=game-1,sticky='ew',padx=(0,10 if game<3 else 0),ipady=8)
            self.buttons.append(button)
        dashboard=tk.Frame(self,bg=PANEL,padx=18,pady=14);dashboard.pack(fill='x')
        self.title=tk.Label(dashboard,text='小游戏',bg=PANEL,fg=TEXT,font=(FONT,19,'bold'));self.title.pack(side='left')
        self.stop_button=ttk.Button(dashboard,text='结束游戏 / 返回普通灯效',command=stop);self.stop_button.pack(side='right')
        self.score=tk.Label(dashboard,text='得分 0',bg=PANEL,fg=CYAN,font=(FONT,20,'bold'));self.score.pack(side='right',padx=25)
        self.timer=tk.Label(dashboard,text='等待开始',bg=PANEL,fg=TEXT,font=(FONT,15));self.timer.pack(side='right',padx=10)
        self.message=tk.Label(self,text='连接板卡后选择游戏',bg=BG,fg=CYAN,font=(FONT,12),anchor='w')
        self.message.pack(fill='x',pady=(12,5))
        self.rules=tk.Label(self,text=RULES[0],bg=PANEL,fg=MUTED,font=(FONT,11),anchor='w',justify='left',padx=16,pady=12,wraplength=1100)
        self.rules.pack(side='bottom',fill='x',pady=(12,0))
        self.matrix=GameMatrix(self);self.matrix.pack(fill='both',expand=True)

    def refresh(self,status,fresh,can_start,can_stop,transport_message=''):
        for button in self.buttons:button.configure(state='normal' if can_start else 'disabled')
        self.stop_button.configure(state='normal' if can_stop else 'disabled')
        if status:
            self.title.configure(text=NAMES[status.game])
            self.score.configure(text=f'得分 {status.score}')
            if status.phase==1:
                timer=f'准备 {status.seconds} 秒';message='请先松开全部按键，倒计时结束后开始'
            else:
                timer=f'{"剩余" if status.game==2 else "用时"} {status.seconds} 秒'
                message={0:'选择游戏开始新的一局',2:'进行中 · 使用实板按键',3:REASONS[status.reason],4:'通关！已填满活动区域'}.get(status.phase,'等待板卡')
            if status.game==2 and status.phase in (2,3):message+=f'　·　漏按 {status.misses}'
            if not fresh:message='连接未就绪 · 此处是最后收到的状态，板上游戏可能仍在运行'
            elif transport_message:message=transport_message
            self.timer.configure(text=timer);self.message.configure(text=message)
            self.rules.configure(text=RULES[status.game])
        else:
            self.message.configure(text=transport_message or '等待游戏固件状态；普通灯效固件不支持此页')
        render=(status.game,status.pixels) if status else None
        if render!=self.last_render:
            self.matrix.render(status);self.last_render=render
