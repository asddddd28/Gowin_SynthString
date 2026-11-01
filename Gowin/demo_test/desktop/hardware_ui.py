"""综合硬件状态总览；每张卡使用本模块的新鲜度，不掩盖局部断连。"""
import tkinter as tk
from tkinter import ttk

class HardwarePanel(ttk.Frame):
    def __init__(self,parent,navigate):
        super().__init__(parent)
        self.columnconfigure((0,1,2),weight=1,uniform='hardware')
        self.rowconfigure((1,2),weight=1)
        self.title=ttk.Label(self,text='硬件综合调试 · 等待综合固件',font=('Microsoft YaHei UI',18,'bold'))
        self.title.grid(row=0,column=0,columnspan=3,sticky='w',padx=20,pady=15)
        self.cards=[]
        for index,(name,target) in enumerate((('32 键 · 灯效 / 游戏','keyboard'),('5 路编码器','encoder'),('摇杆','joystick'),('左触摸板','touchpad'),('右触摸板','touchpad'),('FPGA 六弦吉他','touchpad'))):
            card=tk.Frame(self,bg='#132236',padx=18,pady=15)
            card.grid(row=1+index//3,column=index%3,sticky='nsew',padx=10,pady=10)
            tk.Label(card,text=name,bg='#132236',fg='#e4edf8',font=('Microsoft YaHei UI',13,'bold'),anchor='w').pack(fill='x')
            status=tk.Label(card,text='等待数据',bg='#132236',fg='#8194ad',font=('Microsoft YaHei UI',10),anchor='nw',justify='left',wraplength=350)
            status.pack(fill='both',expand=True,pady=12)
            ttk.Button(card,text='查看详情 →',command=lambda key=target:navigate(key)).pack(anchor='w')
            self.cards.append(status)
        ttk.Button(self,text='打开 FPGA 小游戏',command=lambda:navigate('games')).grid(row=3,column=2,sticky='e',padx=20,pady=12)
        self.footer=ttk.Label(self,text='各模块持续并行采集 · 吉他页启用时播放电脑声音',style='Muted.TLabel')
        self.footer.grid(row=3,column=0,columnspan=2,sticky='w',padx=20)

    def refresh(self,app,now):
        hub=app.protocol=='hub'
        identity=app.hardware_identity
        self.title.configure(text=('硬件综合调试 · '+('实时' if app.input_kind=='live' else '历史回放')+f' · 固件 {identity.build:04X}') if hub and identity else '硬件综合调试 · 当前为单功能固件 / 等待连接')
        key_count=sum(app.model.fresh(i,now) for i in range(32))
        board=app.board.last_status if app.board else None
        values=[(key_count==32,f'有效数据 {key_count}/32 键\n按下 {sum(app.model.pressed)} 键\n板上校准：'+('已生效' if board and board.configured else '待下发')+f'\nADC 显示 {app.rate_scans:.1f} 轮/秒')]
        channels=app.encoders.channels
        enc_count=sum(c.fresh(now) for c in channels)
        values.append((enc_count==5,f'有效数据 {enc_count}/5 路\n边沿位置：'+ ' / '.join(str(c.edges) for c in reversed(channels))+'\n累计非法跳变：'+str(sum(c.invalid for c in channels))))
        joy=app.joystick
        values.append((joy.fresh(now),f'方向：{app.joystick_page.pad.direction}\n按压次数：'+(str(joy.record.presses) if joy.record else '—')))
        for i in range(2):
            r=app.touchpad.records[i];fresh=app.touchpad.fresh(i,now)
            values.append((fresh,f'采集：'+('正常' if fresh else '等待 / 超时')+f'\n地址：'+(f'0x{r.address:02X}' if r else '—')+f'\n触摸位图：'+(f'{r.mask:03X}' if fresh else '—')+f'\nFPGA 采样约 {app.guitar.rates[i]:.0f} Hz'))
        snapshot=app.guitar.snapshot();overflows=sum(r['dropped'] for r in snapshot['boards'] if r)
        values.append((any(now-t<.6 for t in app.guitar.received),f'划弦判断：FPGA\n已播放 {snapshot["total"]} 根弦\n事件队列溢出 {overflows}\n'+app.guitar_audio.status))
        for label,(fresh,text) in zip(self.cards,values):
            label.configure(text=text,fg='#4ec9c4' if fresh else '#e8bb6e')
