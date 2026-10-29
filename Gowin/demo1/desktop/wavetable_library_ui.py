"""多帧资源查看、周期预览及经已有双帧协议上传；不宣称硬件驻留整库。"""
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

from wavetable import load_surge_frames, resample_frame
from wavetable_bank import MAX_BYTES, encode_bank
from wavetable_library import load_library, make_resource
from ui_theme import BG, FONT, size_window, scale_size


class LibraryPanel(tk.Toplevel):
    def __init__(self, parent, upload, initialdir, on_close):
        super().__init__(parent)
        self.title('波表资源库 · 电脑端选帧')
        size_window(self, 840, 660, (720, 580))
        self.upload = upload
        self.on_close = on_close
        self.initialdir = str(initialdir)
        self.resources = []
        self.status = tk.StringVar(value='打开完整波表或 TSLIB.JSN 资源库；FPGA 每次只接收所选的相邻两帧。')
        self.position = tk.DoubleVar(value=0)
        self.selection_info = tk.StringVar(value='尚未选择资源')
        controls = ttk.Frame(self,padding=14);controls.pack(fill='both',expand=True)
        ttk.Label(controls,text='波表工作区',font=(FONT,20)).pack(anchor='w',pady=(0,12))
        ttk.Button(controls,text='打开 WT / WAV / TSWT / 资源库…',command=self.open_file).pack(anchor='w')
        listing=ttk.Frame(controls);listing.pack(fill='both',expand=True,pady=10)
        self.tree = ttk.Treeview(listing,columns=('id','revision','frames'),show='tree headings',height=7)
        self.tree.heading('#0',text='资源');self.tree.heading('id',text='ID')
        self.tree.heading('revision',text='版本');self.tree.heading('frames',text='帧数')
        self.tree.column('#0',width=350);self.tree.column('id',width=100)
        self.tree.column('revision',width=70);self.tree.column('frames',width=70)
        scroll=ttk.Scrollbar(listing,orient='vertical',command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.pack(side='left',fill='both',expand=True);scroll.pack(side='right',fill='y')
        self.tree.bind('<<TreeviewSelect>>',lambda event:self.preview())
        row=ttk.Frame(controls);row.pack(fill='x')
        ttk.Label(row,text='整张波表位置 %').pack(side='left')
        ttk.Scale(row,from_=0,to=100,variable=self.position,command=lambda value:self.preview()).pack(side='left',fill='x',expand=True,padx=12)
        ttk.Spinbox(row,from_=0,to=100,increment=.1,textvariable=self.position,width=8,command=self.preview).pack(side='left')
        self.position.trace_add('write',lambda *args:self.preview())
        ttk.Label(controls,textvariable=self.selection_info).pack(anchor='w',pady=7)
        self.canvas=tk.Canvas(controls,height=scale_size(self,150),bg=BG,highlightthickness=0)
        self.canvas.pack(fill='x');self.canvas.bind('<Configure>',lambda event:self.preview())
        ttk.Label(controls,text='蓝色：前帧   绿色：后帧   白色：混合预览').pack(anchor='w',pady=5)
        ttk.Button(controls,text='上传所选位置到当前音键',command=self.upload_selected).pack(anchor='w',pady=8)
        ttk.Label(controls,textvariable=self.status,wraplength=740).pack(fill='x',pady=6)
        self.protocol('WM_DELETE_WINDOW',self.close)

    def load(self, path):
        """先完整校验再换视图，加载失败保持原资源列表。"""
        path=Path(path)
        if path.suffix.lower() == '.jsn' or path.name.upper() == 'TSINDEX.BIN':
            resources=load_library(path)
        else:
            if path.suffix.lower() in ('.tswt','.bin'):
                if path.stat().st_size>MAX_BYTES:raise ValueError('TSWT资源过大')
                data=path.read_bytes()
            elif path.suffix.lower() in ('.wt','.wav'):
                data=encode_bank([resample_frame(frame) for frame in load_surge_frames(path)])
            else:raise ValueError('请选择 WT、Surge WAV、TSWT 或 TSLIB.JSN')
            resources=[make_resource(1,1,path.stem[:80],data)]
        self.resources=resources
        for item in self.tree.get_children():self.tree.delete(item)
        for i,r in enumerate(resources):
            self.tree.insert('',tk.END,iid=str(i),text=r.title,values=(f'{r.resource_id:08X}',r.revision,r.frame_count))
        self.tree.selection_set('0');self.position.set(0)
        self.initialdir=str(path.parent)
        self.status.set(f'已校验 {len(resources)} 个资源。整库保存在电脑/文件中；板上仍共享一对帧。')
        self.preview()

    def open_file(self):
        path=filedialog.askopenfilename(parent=self,initialdir=self.initialdir,
            title='多帧波表或校验资源库',filetypes=[('波表与资源库','*.wt *.wav *.tswt *.jsn *.bin')])
        if path:
            try:self.load(path)
            except (ValueError,OSError,TypeError) as error:messagebox.showerror('资源库加载失败',str(error),parent=self)

    def selected_pair(self):
        selection=self.tree.selection()
        if not selection:raise ValueError('请先选择资源')
        return self.resources[int(selection[0])].pair(self.position.get())

    def preview(self):
        try:frames,job=self.selected_pair()
        except (ValueError,tk.TclError,IndexError):return
        self.selection_info.set(f"位置 {self.position.get():.2f}% · 帧 {job['first']} / {job['second']} · 帧间混合 {job['fraction']*100/65536:.2f}%")
        self.canvas.delete('all')
        width=max(1,self.canvas.winfo_width());height=170
        self.canvas.create_line(0,height/2,width,height/2,fill='#344052')
        blend=[a*4+((b-a)*4*job['fraction']//65536) for a,b in zip(*frames)]
        for samples,color in (([v*4 for v in frames[0]],'#59adff'),([v*4 for v in frames[1]],'#59dfb4'),(blend,'#edf3fc')):
            points=[]
            for i in range(0,1024,4):points.extend((i*width/1023,height/2-samples[i]*(height*.44)/131072))
            self.canvas.create_line(*points,fill=color,width=1.5)

    def upload_selected(self):
        try:
            frames,job=self.selected_pair()
            if self.upload(frames,job['fraction']):
                self.status.set('正在上传相邻两帧；资源、音键参数和帧位置全部确认后，下次起音生效。')
            else:self.status.set('请先连接 FPGA，并等待其他上传结束。')
        except (ValueError,tk.TclError) as error:messagebox.showerror('无法上传',str(error),parent=self)

    def close(self):
        self.on_close()
        self.destroy()
