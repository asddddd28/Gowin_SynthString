# Tauri Studio（2026-10-24，新增桌面版本）

新版位于 `../desktop-tauri/release/TangSynthStudio/TangSynthStudio.exe`，请保留整个发布目录。使用 Tauri 2 + React 界面，保留 Python 串口与上传校验。操作、构建及能力边界见 [Studio 说明](../desktop-tauri/README.md)。旧版程序及 FPGA 位流保留。

---

# 基础音色库（2026-10-12，历史桌面版本）

运行 `release_basic/TangSynth32/TangSynth32.exe`，保留整个文件夹。新版包含“基础音色库…”和此前的“资源库…”；固件继续使用 `output/demo1_pair_31002.fs` 或 `output/demo1_pair_31004.fs`，选择已确认通信正常的底板版本。本轮未生成新版位流，旧程序/位流目录均保留。

1. 打开右上“基础音色库…”，随附目录自动校验并加载16个音色。前三个是正弦贝斯、柔和三角、方波主音，另有FM电钢琴/钟声/贝斯、AM颤音、环形金属，以及8个AKWF单周期音色。
2. 不接板子也可点“电脑试听 C3 / C4 / C5”，音频通过Windows默认输出播放，“停止试听”或关闭音色窗口停止。这是独立的桌面浮点近似参考，**不是Surge渲染、FPGA录音或定点等价输出**。总览在 `basic_bank/MIXDEMO.WAV`，按目录顺序每个音色一个C4短音。
3. 连接DEBUG USB串口，收到FPGA响应后，在主窗口选择目标键。音色窗口选择音色，点击“应用并上传此键”。内置波形/FM/AM只传参数；AKWF将一帧复制成双帧，通过原协议上传2048个int16点，资源CRC/提交确认后才保存并发送该键的完整音色参数与零帧位置。
4. 以主窗口“逐键参数已由FPGA校验确认”为完成标志，再按主窗口显示的电脑键盘映射或鼠标发音。上传中切换GUI所选键不改变已捕获目标。波表上传失败不改本地音色；参数未确认时该键禁止起音，断线后必须重新确认。

板上仍只有**一对共享帧**，更换AKWF资源影响所有自定义波表键；8个内置/FM/AM音色可独立逐键配置。当前资源不带mip抗混叠，先在中低音验证。管风琴、笛音、弦乐等名字描述单周期素材类别，不能等同于完整真实乐器采样。复位后波表RAM清空，需要重传；此批目录尚未实现逐键独立资源绑定/驻留或SD自动加载，不要将保存配置等同于保存板上波表。

`basic_bank/FEATURES.JSN` 逐音色列出需要的模块和后续目标；`SOURCES.JSN` 保存来源、固定提交、SHA256及转换参数，`LICENSE.md` 保留原许可证。[AKWF原作者仓库](https://github.com/KristofferKarlAxelEkstrand/AKWF-FREE) 标注CC0，原素材为600点单声道PCM16，第一批显式去直流、归一化到0.90并周期线性重采样为1024点。原WAV保存在工程 `vendor/akwf_mini`。

工程根目录可以离线重建，输出为 `output/basic_bank_v1`；不同的已存在目标不会被覆盖。旧的 `output/basic_bank` 是保留的初版草稿，当前程序使用v1目录。

```powershell
desktop/.venv/Scripts/python.exe scripts/prepare_basic_bank.py
desktop/.venv/Scripts/python.exe scripts/convert_single_cycle.py vendor/akwf_mini/AKWF/AKWF_eorgan/AKWF_eorgan_0001.wav --single-cycle --output output/single_cycle_demo.tswt
desktop/.venv/Scripts/python.exe -m unittest discover -s desktop -p "test_*.py"
desktop/.venv/Scripts/python.exe scripts/record_basic_bank_results.py
```

转换工具只接受明确为一个周期的16..4096点PCM16单声道WAV，输出TSWT可从“资源库…”打开。普通乐器录音继续走PCM采样流程，Surge WAV入口仍要求其帧元数据，未改为自动猜测波表。

当前86项桌面测试通过，含实际Tk控件、模拟串口、损坏目录/资源/试听拒绝、素材转换、可重建性及上传事务；另有EXE启动与发布文件摘要核对，证据见工程 `reports/basic_bank_validation.json`。没有实体串口、SD或音频验收，预取原型和全RTL严格门禁的未通过状态见工程质量状态。以下历史验证数字只对应各自发布版本。

---

# 完整波表资源库（2026-10-12，历史桌面版本）

运行 `release_library/TangSynth32/TangSynth32.exe`，保留整个文件夹。配套固件继续使用 `output/demo1_pair_31002.fs` 或 `output/demo1_pair_31004.fs`；当前增量没有生成新版位流。电脑程序仍使用同一份逐键配置和串口协议。

1. 点击主窗口“资源库…”，打开随附 `wavetable_library/TSLIB.JSN`。两个示例分别是正弦→锯齿63帧、正弦→方波31帧；也可打开原生WT/WAV或完整TSWT文件。
2. 选择资源，用0..100%位置选帧。图中蓝/绿线为相邻帧，白线为混合后的单周期。100%会使用最后一帧两次，单帧资源也支持。
3. 连接已有双帧固件，选定目标键后点击上传。程序等待波表CRC/提交确认，再上传该键的音色参数和帧位置；全部确认后再演奏。上传期间切换GUI所选键不会改变已捕获的目标。

**目前板上仍只有一对共享帧。** 上传新表会改变所有使用自定义波表的键；整张资源留在电脑/文件中，当前没有连续动态扫过全部帧，也没有逐键独立资源驻留。

资源库的 `TSINDEX.BIN`、`TSLIB.JSN`、`00000001.BIN`、`00000002.BIN` 可保存到现有64GB exFAT卡。为之后的根目录读取阶段准备时，复制文件夹内这四个文件到卡的根目录；无需改变卡格式。现在的固件尚不会读取它们，不把文件复制成功视为硬件加载成功。电脑端通过读卡器挂载后可直接打开卡上的 `TSLIB.JSN`，由操作系统读取文件。

当前73项桌面测试、4项旧TSWT兼容测试、6项exFAT稀疏镜像测试以及EXE启动检查通过，证据为 `reports/wavetable_library_validation.json`。exFAT读取代码是Python参考模型；SD块接口、exFAT硬件执行、DDR加载、缓存仲裁和实际卡/音频验收仍待完成。后台预取RTL原型的24个事务/故障测试及独立综合通过，但严格门禁未通过，没有接入音频路径，详见工程质量状态。

以下保留双帧固件阶段的操作和验证记录。

---

# 双帧波表与逐键位置（历史桌面版本，同一固件）

运行 `release_pair/TangSynth32/TangSynth32.exe`，保留整个 `TangSynth32` 文件夹。固件为工程根目录的 `output/demo1_pair_31002.fs` 或 `output/demo1_pair_31004.fs`；沿用此前已经串口通信成功的底板版本。旧 bridge 程序和 banked 位流保留，新功能需要这次的程序与固件配套。DEBUG USB 连接、音量和电脑键盘映射仍按下文及 [精度版说明](PRECISION_README.md) 操作。配置继续保存在 `%LOCALAPPDATA%/TangSynth32/settings-pcm.json`。

## 上传双帧并配置每个键

1. 关闭旧版 TangSynth32，烧录匹配底板版本的 pair 位流，打开新程序并连接 DEBUG UART。连接确认后选择目标音键。
2. 点击“导入双帧”，选择 Surge 原生 `.wt` 或带 Surge 波表帧信息的 `.wav`。输入第一帧编号，编号从 0 开始；程序选择它和紧接着的下一帧，分别重采样到 1024 点。至少需要两帧，普通录音 WAV 仍应走 PCM 采样流程。
3. 程序松开音符后上传 2048 个 int16 点，校验长度、CRC、token 和 generation，再确认活动资源标志。尾音未结束时固件会等待零活动声部边界；失败或中止保留旧活动资源。上传成功后，最初选择的目标键自动使用自定义波表，并继续等待该键参数确认。
4. 右键音键打开编辑器，设置 A 波形为“自定义波表”，设置“双帧位置 %（下次起音）”，再点击“应用此音键”。位置 0 接近第一帧，100 接近第二帧；收到参数及位置回读确认后再起音试听。B 若选择自定义波表，也使用同一资源和位置。
5. 可将不同音键设为 0、50、100 等位置。已经按住的音符保留原位置，下次起音或重触发使用新值。复位或断电后资源 RAM 清空，需要重新上传。

目前所有自定义波形键共享**一对波表帧**，每键独立的是混合位置和原有音色参数，尚无逐键独立波表资源库。更换这对帧影响所有使用自定义表的键。位置是静态起音快照，尚未实现 LFO/包络动态扫描。GUI 的 100% 编码为 65535/65536，因此略小于严格的第二帧端点。两级线性插值与 Surge 的带限、变形、unison 算法仍有差异。

旧固件可继续使用单帧导入和零位置；程序会在发送双帧载荷前检查能力，拒绝不支持的新协议。非零位置需要 pair 固件。位置写入与原有 18 字参数分别确认，如果位置回读失败，参数可能已生效，界面会报告未确认并禁止把该键当作已同步；重连新固件后重新上传。

## 验证与后续工作

本版桌面 **65 项测试**通过，覆盖旧功能、双帧协议、固件能力探测、状态包碎片/损坏、CRC/token/代次确认、逐键回读及 GUI 选择目标。新 EXE 已重新打包并通过进程启动检查。硬件冻结副本的 **17 组 RTL 回归**及两板型 Gowin 布局布线通过：32 声部最大 455/512 拍，输出增益另加一拍，BSRAM 117/118，DSP 45/118。31002 建立/保持最小余量 0.017/0.004 ns，31004 为 0.039/0.002 ns，均无违例，但余量很小。证据为工程 `reports/wavetable_pair_validation.json`。整个 RTL 严格风格门禁仍未通过；尚未实体烧录、UART 联调、听音或 Surge 参考音频比较。

Surge OSC 桥接仍自动映射四项音量 ADSR，其余参数只显示；操作见下方历史桥接说明。离线 TSWT 工具仍可保存全部帧，但 GUI 此次从原生 WT/WAV 选择相邻两帧，不能直接加载 TSWT。SD/FAT32/DDR 读取、多资源切换、带限、调制、滤波器和效果链仍待实现。详细进度和下一阶段顺序见工程 [计划第 12 节](../docs/task_plan.md#12-双帧播放与逐键位置2026-10-12)。

以下保留此前发布版本的说明，当前固件与程序以上方为准。

---

# Surge 参数桥接与波表 RAM 优化（2026-10-12，历史）

运行 `release_bridge/TangSynth32/TangSynth32.exe`，保留整个 `TangSynth32` 文件夹。本轮固件为 `output/demo1_banked_31002.fs` 或 `output/demo1_banked_31004.fs`，选择已经能正常串口通信的底板版本；电脑程序和串口协议沿用桥接版。它保留上一版的周期波表插值，优化 RAM 布局，为后续多帧缓存腾出空间。旧 interpolated 固件保留；更早的 precision 固件也能连接，但没有硬件波表插值。DEBUG USB 连接方式和音量试听见 [精度版说明](PRECISION_README.md)。配置保存在 `%LOCALAPPDATA%/TangSynth32/settings-pcm.json`。

## 从 Surge 读取参数并配置一个硬件音键

1. 打开 Surge XT 主菜单 → `OSC Settings` → `Show OSC Settings...`。同时启用 OSC 输入和输出：输入端口 `53280`，输出地址 `127.0.0.1`，输出端口 `53281`，点击 Apply/OK。汉化界面可能显示对应中文菜单。
2. 关闭旧版 TangSynth32，打开本版并连接 DEBUG UART。点击音键选择目标，再打开“Surge 参数桥接…”，点击“连接读取”。端口如有修改，两端必须一致。
3. 桥接窗口列出软件参数及显示读数。选择场景 A 或 B，停止调节 Surge 后检查包络预览，再点击“应用 A/D/S/R 到当前音键并上传”。只改该键的音量包络，其余音色参数保留当前配置；连接 FPGA 时必须收到确认才算上传成功。离线应用只保存配置。
4. 可导出和载入 JSON 参数快照。它是桥接窗口的参数记录，不是 Surge 原生音色文件；UDP 读取也不是原子音色导出。

当前自动映射只有 Attack、Decay、Sustain、Release。程序按 Surge 的参数范围把归一化值还原为时间和持续电平，不把 0..1 直接当毫秒。启用节拍同步、释放 Freeze 或时间超出硬件界面 5000 ms 上限时，会明确拒绝应用。Surge 的包络曲线、模拟模式和释放行为与当前线性硬件包络不同，映射后不保证声音相同。振荡器、滤波器、效果、调制矩阵及场景组合目前只显示，不自动映射。

## 导入 Surge 波表

可直接选择 Surge 原生 `.wt`，或在 Surge 振荡器波形区域菜单选择 `Export Wavetable to File...` 后导入其导出的 `.wav`。后者必须含 Surge 的波表帧信息；普通录音 WAV 请走 PCM 采样转换流程。

点击主窗口“导入波表”，选择文件。多帧文件需选择一个帧号，编号从 0 开始；电脑端把这一周期线性重采样到 1024 点后，走原有带校验和确认的串口上传流程。新插值固件按相位小数对相邻样点插值，末点回绕到同一银行的第零点，支持正弦和自定义波表。当前 FPGA 只保存一个共享自定义波表，所有使用自定义波形的音键都会受此次上传影响。仍不支持逐键独立波表库、多帧渐变或抗混叠。上传数据保存在 RAM，复位或断电后需要重传。

## 互通进度与验证

桥接阶段桌面端 57 项测试通过，覆盖实际本机 UDP 收发测试替身、异常报文、参数单位换算、只更新选定音键、上传确认，以及桥接窗口生命周期。另读入了三份真实 Surge 出厂 `.wt`；导出 WAV 的格式依据当前 Surge 源码构造独立测试向量。打包及启动检查见 `reports/surge_bridge_validation.json`。本轮未改桌面程序，核对 EXE 摘要后沿用该版本，没有重新运行这 57 项测试。

之前对运行中 Surge 默认端口做只读查询时，没有收到参数回包；尚需开启软件 OSC 并完成真实软件联调。本轮 RAM 优化固件通过 14 组 RTL 仿真和两板型布局布线，见 `reports/wavetable_port_validation.json`。32 声部每帧最大计算仍为 359/512 拍，输出增益另加 1 拍；BSRAM 为 109/118，DSP 为 37/118。31002 建立/保持最小余量 0.153/0.023 ns，31004 为 0.027/0.023 ns，均无违例，但后者余量很小，继续扩展需重新验证。上一阶段正弦查表模型 RMS 从 328.14 降至 0.70 个 18 位 LSB，属于查表误差，不代表 DAC 信噪比或 Surge 音色等价。新增双帧数学核心严格检查通过，整个旧 RTL 严格门禁仍未通过。尚未烧录、连接实体 FPGA 或听音。

原生 FXP 的结构读取和资源盘点工具为 `scripts/audit_surge_patches.py`，在工程根目录执行 `desktop/.venv/Scripts/python.exe scripts/audit_surge_patches.py`。已扫描源码中 3008 份音色，记录参数、调制路由及嵌入波表尺寸，旧元数据兼容处理也单独记录；它尚未接入 GUI，不是完整音色导入或硬件播放器。

SD 卡格式化只是存储准备，当前 FPGA 尚未实现 SD 控制器、FAT32 文件读取、音色库缓存和切换。距离“软件参数/一个波表周期送到硬件”的验收主要剩真实 OSC、串口和听音闭环；距离“完整软件音色等价运行”还需扩展 DSP 和存储架构。详细边界见 [工程计划第 11 节](../docs/task_plan.md#11-波表存储优化与双帧核心2026-10-12)，完整 DSP 路线在第 10 节。

## 多帧资源的开发准备

`scripts/prepare_wavetable_bank.py` 可把原生 WT 或带 Surge 帧信息的 WAV 的所有帧按原顺序保存为 `.tswt`。这是离线开发工具；当前 GUI 仍选择一个帧，现有 UART 和 SD 均不能加载 `.tswt`。在工程根目录执行，例如：

```powershell
desktop/.venv/Scripts/python.exe scripts/prepare_wavetable_bank.py "D:/Projects/ai/desktop-synth/resources/data/wavetables/Basic/Sine To Sawtooth.wt" --output output/wavetables/Sine_To_Sawtooth.tswt --report reports/wavetable_bank_sine_saw.json
```

已生成 `Sine_To_Sawtooth.tswt`（63 帧）和 `Sine_To_Square.tswt`（31 帧），每帧 1024 个 int16 点，包含版本、尺寸和载荷 CRC32。转换使用线性重采样，不包含带限 mip 或完整音色参数。新 `WavetableMorph.v` 已单独验证两帧间插值，尚需缓存取数、声部调度和资源上传接入后才能在板上使用。

以下为早期版本说明；当前程序、固件、逐键参数及配置路径以上述说明为准。

---

# 键盘修复 v2（2026-10-01）

运行 `release_keyboard_v2/TangSynth32/TangSynth32.exe`，关闭旧 App 后重新连接串口。无需重烧 FPGA，沿用原设置。

修正 Windows Tk 的 Num Lock 状态（0x08）被当成 Alt 而过滤全部音键的问题；Windows Alt 使用 0x10，并兼容 Tk 的 Alt 标志 0x20000。Num Lock / Caps Lock / Scroll Lock 不再禁止演奏。保留上一版按钮焦点修复。

新增回归先在旧代码上复现失败，再验证修复：15 项测试通过，日志在 reports/gui_numlock_before.log 和 gui_numlock_after.log。系统级键盘注入未完成，板上听测待确认。

依据：https://github.com/tcltk/tk/blob/core-8-6-branch/win/tkWinKey.c （KeycodeToKeysym 的 Mod1Mask / Mod2Mask）。

# 键盘修复版（2026-10-01）

请关闭旧程序，再运行 `release_keyboardfix/TangSynth32/TangSynth32.exe`（标题含“键盘修复版”）。沿用原设置，不用重烧 FPGA。修复连接按钮、演奏复选框获得焦点后键盘被忽略的问题；映射按键优先于按钮默认快捷动作，输入框/下拉框编辑时仍不演奏。启用“键盘演奏”，在本窗口内按音键上显示的映射键，底部会显示收到的按键。若中文输入法占用字母键，请切换英文输入。

已通过 13 项测试，包含真实 Tk 事件分发下按钮焦点的起音/松键、映射空格不误触按钮及文本编辑保护。尚未用实体键盘与 FPGA 联调此修复。

# Tang Synth 32

Windows 桌面控制程序：运行 `release/TangSynth32/TangSynth32.exe`。整个 TangSynth32 文件夹一起保留，不能只拷贝 exe。源码运行方式：安装 requirements.txt 后执行 `python app.py`；开发环境已在 `.venv`。dist 目录为初次预览打包，正式测试用 release 目录。

## 连接

1. 用数据线连接板载 **DEBUG USB**，不是 CH569 USB。FPGA 烧录下述 UART32 文件。
2. 在程序刷新串口。可以通过拔插 DEBUG USB 比较新增的 COM 口；端口号可能变化，不固定为 COM7。
3. 点击连接。只有收到通过校验的 FPGA 状态包才显示“FPGA 已响应”。未响应 3 秒会断开并提示。
4. 程序自动配置 32 声部、单振荡器和当前公共音色。鼠标左键按住音键发声，松开释放；也可使用映射的电脑键盘按键。

## 底板版本未知时

先用 SRAM Program 试 `output/demo1_uart32_31004.fs`（RX V14）。若串口确认正确仍无 FPGA 响应，再试 `output/demo1_uart32_31002.fs`（RX Y14）。两者 TX 都是 U15，RX 均为输入，不向对方驱动电平。不要在尚未通信成功时固化 Flash。连接无响应也可能是 USB 线、选错串口、其他串口程序占用、板卡供电或 DEBUG 固件问题，不能立即认定版本不同。

当前 `demo1.gprj` / `src/constr1.cst` 默认是 **31004 候选**，不是已经识别的硬件版本。也可打开 `demo1_uart_31002.gprj` 或 `demo1_uart_31004.gprj`，它们引用各自 CST。

## 32 个音键

默认 MIDI 48..79（C3..G5），每键可独立设置名称、音高 0..127、力度 1..127、电脑键盘按键。右键音键打开对应编辑内容；点击映射按钮后按一个键，再点“应用此音键”。重复映射会被拒绝。使用 Windows 虚拟键码，字母键的位置不受大小写影响；建议英文输入法，避免输入法拦截。

32 键是可配置音键数量；完整32声部文件使用两组16声部并行引擎。GUI Note ID 为32..47和48..63，分别使用一组，因此32个GUI键可同时分配；普通电脑键盘的多键无冲限制仍然存在。本地和弦ID0..7也使用低组，同组超过16音时会组内偷音，即使另一组有空闲。带8voice_probe字样的临时联调文件只支持8个同时发声，但仍可使用全部32个映射键。

ADSR、波形和音量是公共参数，点击“应用音色”提交。A 是从零到峰值的时间；D 是峰值到 S 的时间；R 是从 S 到零的时间。实际为线性、整数步进，显示时间是目标值；提前松键会从当前电平释放，实际时长不同。0 ms 表示该阶段立即完成。若 S=0，R 的参考距离为零，当前实现释放步长为零即立即结束。

配置自动保存到 `%LOCALAPPDATA%/TangSynth32/settings.json`；支持 JSON 导入导出。导出的是已应用配置，编辑框尚未应用的内容不会导出。

## 停止行为

- Esc / 紧急停止：清发送队列，发送 PANIC，立刻终止全部声部。
- 失去窗口焦点：发送各已按音键的 NoteOff，按 ADSR 自然释放。
- 正常断开/关闭程序：发送 PANIC 再关闭端口。
- USB 拔出或程序异常退出：串口控制会话缺少有效包约 2 秒后，FPGA 清空全部声部。GUI 每 0.5 秒查询状态作为心跳。
- 原板载 KEY0/KEY1/KEY2 保留。KEY0 复位会恢复 FPGA 默认参数，复位后在 GUI 再点“应用音色”；KEY2 改音色不会同步 GUI 下拉框。

音频仍由板载耳机口输出，GUI 不在电脑上合成声音。本版本不启用空闲自动关闭耳放。

## 开发验证

`python -m unittest test_protocol test_app test_transport`。test_protocol 单独运行还会生成 FPGA 仿真字节向量：随后 `python scripts/run_sim.py --voices 32 --test uartkeys`（工程根目录）。串口线程使用测试替身验证收发与断线，不代表物理 USB 已测试。

打包：`python -m PyInstaller --noconfirm --clean --windowed --onedir --name TangSynth32 --distpath release app.py`。打包环境版本记录在 requirements-build.lock.txt。
