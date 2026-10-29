"""基础音色选择、来源说明、桌面试听及已确认的逐键上传入口。"""
import tkinter as tk
from tkinter import filedialog,messagebox
import ttkbootstrap as ttk

from basic_bank import load_basic_bank
from ui_theme import style_text, size_window, FONT


def play_wav(path):
    import winsound
    winsound.PlaySound(str(path),winsound.SND_FILENAME|winsound.SND_ASYNC|winsound.SND_NODEFAULT)


def stop_wav():
    import winsound
    winsound.PlaySound(None,0)


class BasicBankPanel(tk.Toplevel):
    def __init__(self,parent,apply,initialdir,on_close,play=play_wav,stop=stop_wav):
        super().__init__(parent)
        self.title('基础音色库 · 16音色')
        size_window(self, 840, 680, (740, 620))
        self.apply=apply;self.initialdir=str(initialdir);self.on_close=on_close;self.play=play;self.stop=stop
        self.sounds=[]
        self.status=tk.StringVar(value='可离线试听；连接FPGA后可应用并上传到主窗口选中的音键。')
        frame=ttk.Frame(self,padding=14);frame.pack(fill='both',expand=True)
        header=ttk.Frame(frame);header.pack(fill='x',pady=(0,12))
        ttk.Label(header,text='基础音色库',font=(FONT,20)).pack(side='left')
        ttk.Button(header,text='打开音色目录',command=self.open_file,bootstyle='secondary outline').pack(side='right')
        search=ttk.Frame(frame);search.pack(fill='x')
        ttk.Label(search,text='搜索名称 / 类别').pack(side='left',padx=(0,12))
        self.query=tk.StringVar()
        self.search_entry=ttk.Entry(search,textvariable=self.query)
        self.search_entry.pack(side='left',fill='x',expand=True)
        listing=ttk.Frame(frame);listing.pack(fill='both',expand=True,pady=12)
        self.tree=ttk.Treeview(listing,columns=('category','resource'),show='tree headings',height=8)
        for column,label in (('#0','音色'),('category','类别'),('resource','素材')):self.tree.heading(column,text=label)
        self.tree.column('#0',width=260);self.tree.column('category',width=140);self.tree.column('resource',width=180)
        scroll=ttk.Scrollbar(listing,orient='vertical',command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.pack(side='left',fill='both',expand=True);scroll.pack(side='right',fill='y')
        self.tree.bind('<<TreeviewSelect>>',lambda event:self.show_info())
        self.info=tk.Text(frame,height=6,wrap='word');style_text(self.info);self.info.pack(fill='x')
        row=ttk.Frame(frame);row.pack(fill='x',pady=10)
        ttk.Button(row,text='电脑试听 C3 / C4 / C5',command=self.preview,bootstyle='primary').pack(side='left')
        ttk.Button(row,text='停止试听',command=self.stop).pack(side='left',padx=8)
        ttk.Button(row,text='应用并上传此键',command=self.upload).pack(side='right')
        ttk.Label(frame,textvariable=self.status,wraplength=720).pack(fill='x')
        self.query.trace_add('write',lambda *_:self.filter_sounds())
        self.protocol('WM_DELETE_WINDOW',self.close)

    def selected(self):
        selection=self.tree.selection()
        if not selection:raise ValueError('请先选择音色')
        return self.sounds[int(selection[0])]

    def load(self,path):
        sounds=load_basic_bank(path)
        self.stop();self.sounds=sounds
        self.query.set('')
        self.status.set(f'已校验 {len(sounds)} 个音色及参考试听。波表音色共用板上的一对帧。')

    def filter_sounds(self):
        selected=self.tree.selection()
        query=self.query.get().strip().casefold()
        for item in self.tree.get_children():self.tree.delete(item)
        for index,sound in enumerate(self.sounds):
            if query not in (sound.title+' '+sound.category).casefold():continue
            self.tree.insert('',tk.END,iid=str(index),text=sound.title,values=(sound.category,
                '内置波形' if sound.resource_id is None else f'AKWF · {sound.resource_id:08X}'))
        visible=self.tree.get_children()
        if visible:self.tree.selection_set(selected[0] if selected and selected[0] in visible else visible[0])
        self.show_info()

    def show_info(self):
        try:sound=self.selected()
        except (ValueError,IndexError):
            self.info.configure(state='normal');self.info.delete('1.0','end')
            self.info.insert('end','没有匹配的音色。请调整搜索条件。');self.info.configure(state='disabled')
            return
        p=sound.profile
        self.info.configure(state='normal');self.info.delete('1.0','end')
        self.info.insert('end',f'{sound.title} · {p["mode"]}\n音量包络：A {p["attack"]} / D {p["decay"]} / S {p["sustain"]}% / R {p["release"]} ms\n{sound.description}\n')
        self.info.insert('end','电脑试听是近似参考，不是FPGA录音。AKWF换表会影响其他使用自定义波表的键。')
        self.info.configure(state='disabled')

    def preview(self):
        try:
            sound=self.selected();self.play(sound.preview)
            self.status.set('电脑参考试听：'+sound.title+'。未向FPGA发送音符。')
        except (ValueError,OSError,RuntimeError) as error:messagebox.showerror('试听失败',str(error),parent=self)

    def upload(self):
        try:
            sound=self.selected();profile,frames=sound.upload()
            if self.apply(profile,frames):
                self.status.set('已开始上传 '+sound.title+'；以主窗口的资源/参数确认状态为准。')
            else:self.status.set('请连接FPGA并等待其他上传结束；音色尚未应用。')
        except (ValueError,OSError) as error:messagebox.showerror('音色应用失败',str(error),parent=self)

    def open_file(self):
        path=filedialog.askopenfilename(parent=self,initialdir=self.initialdir,filetypes=[('基础音色目录','*.JSN')])
        if path:
            try:self.load(path)
            except (ValueError,OSError,TypeError) as error:messagebox.showerror('音色库加载失败',str(error),parent=self)

    def close(self):
        self.stop();self.on_close();self.destroy()
