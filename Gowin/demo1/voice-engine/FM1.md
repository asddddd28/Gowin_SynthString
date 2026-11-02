# FM1 / DX7 首批四音色

2026-11-02，候选 RTL。四个原厂音色已经过 Python 数值模型与 RTL 对比；
整板尚未完成50 MHz布局布线验收，也未烧录。原有演奏固件保持不变。

本次完整综合占用40,699/59,904逻辑单元（68%）、21,077寄存器（35%）、
93/118 BSRAM（79%），无锁存器。综合估算Fmax只有13.564 MHz，最慢路径从
声部年龄比较进入事件更新；仍须把分配/校验控制分拍，再重新布局布线。
971/1024拍是逻辑仿真中的周期预算，不能替代此物理时序要求。

## 已接入的音色

| 驻留槽 | 名称 | 原厂位置 | 稳定 Program ID（从0计数） | DX算法 |
| --- | --- | --- | --- | --- |
| 0 | PIANO 2 | A05 | 4 | 5 |
| 1 | ORGAN 1 | A02 | 1 | 32 |
| 2 | BASS 3 | B11 | 42 | 17 |
| 3 | BRASS 2 | C05 | 68 | 5 |

这是从真实原厂参数转换的四个程序，没有用自制近似音色替换原数据。
选型避开尚未支持的 Pitch EG、活跃 DX LFO、自由运行振荡相位和特殊反馈。
例如 PIANO 1 的自由运行相位目前不匹配，所以选 PIANO 2。

容量需要分开理解：**库中128个完整条目、4个同时驻留音色、8个动态复音、每声部6个逻辑算子**。
`assets/fm1/library.json` 保留全部128个名字、算法、原始128字节VMEM、SHA和缺项。
只有上述四个标为 `initial-four`；其他条目是 `blocked` 或 `unqualified`，
不能据此宣称已经支持128个音色。硬件驻留槽不需要立即扩成128份。

## 本次补齐的硬件和软件

- `AxisDxEnvelope`：对数域四段 EG，非线性起音、指数增益、Key Level Scaling
  四类曲线、Key Rate Scaling、Velocity Sensitivity、Output Level。
- `AxisFmOperator`：并行选择原生线性EG或DX对数EG；DX PM和反馈幅度换算，
  两个历史反馈样本。每个模块仍为一个物理计算单元，按声部/算子调度。
- `VoiceSynthEngine`：DX频率比上限64，原生保持16；每声部独立保存音高、力度；
  同一 NoteID 的参数冲突会拒绝，重复按住不重触发。
- 原生/DX之间切换时，若目标槽仍有活动声部，A3提交返回 BUSY10，保留旧音色与草稿。
  等释放尾音结束或明确 panic 后，可用新序号重试提交。不会把线性状态误读为对数状态。
- 严格 SysEx 单音色/32音色库解码、七位数据/长度/校验和检查、VCED/VMEM转换、
  全部32种算法的前向连接表。算法4/6的跨算子反馈暂时禁止。
- 四个原厂程序随板级启动ROM装载，启动命令从64条变为60条；主机可以逐槽更换。

四个音色各自仍有6个算子、独立EG/相位/反馈状态。新增包络在波形计算期间并行完成，
没有增加算子延迟：E0接纳，E9后结果有效（测试记为10个时钟）。
满载 LFO + Voice + Delay/Reverb 的整机仿真仍为971/1024拍。

## 使用方法

以下命令在 `Gowin/demo1/voice-system` 目录执行。**需要编译并通过硬件验收的新固件**，
UART协议仍为5，内核ABI更新为 `0x00010005`。旧App界面尚未接入此协议；本轮提供的是
诊断客户端的音色库装载入口。客户端上传前会检查ABI，拒绝向旧内核发送DX参数。

```powershell
# COM端口按实际连接替换。--new-session只在FPGA重置/重新烧录后使用。
python host/control.py --port COM7 --new-session status

# 启动ROM已装入四个音色，可以直接试音。
python host/control.py --port COM7 play --slot 0 --note 60 --velocity 100 --seconds 2
python host/control.py --port COM7 play --slot 1 --note 60 --velocity 100 --seconds 2
python host/control.py --port COM7 play --slot 2 --note 48 --velocity 90 --seconds 2
python host/control.py --port COM7 play --slot 3 --note 60 --velocity 110 --seconds 2

# 例如把贝斯装进实体键盘当前使用的槽0；库ID与槽号是两个概念。
python host/control.py --port COM7 bank --program 42 --slot 0
```

实体键盘仍按半音连续映射 MIDI48..79，使用槽0；当前扫描器没有测量敲击速度，
所以固定力度100。主机试音支持力度1..127。库装载自动使用递增revision并持久保存，
也可以明确指定 `--revision`。传输超时后用 `recover` 重发相同包，不要新建会话掩盖超时。

离线管理（在 `voice-engine` 目录）：

```powershell
python model/dx7_bank.py list
python model/dx7_bank.py import assets/fm1/factory_A.syx --output imported.json
python model/dx7_bank.py export 42 --output bass.json
python model/compile_voice_patch.py bass.json --slot 0 --output bass-commands.json
```

导入只保存和分析，不会自动修改硬件。普通自定义库导出须明确 `--experimental`，
即使指定此选项，也不会跳过不支持功能的检查。

## 数值与兼容边界

该实现不是逐位相同的 DX7 或 FM1 音源。包络以48828.125 Hz逐样本推进，参考MSFA
速率表从44100 Hz缩放；原版的控制块步进/增益插值不同。256项exp2表与Q26截断，
在测试的对数范围内幅度相对误差小于0.36%；这不是对FM1整机听感误差的测量。
既有1024点插值正弦、载波平均和8复音固定余量也会影响响度。高频比在超过Nyquist时
沿用当前引擎的频率限幅，不能保证全部MIDI音域与DX7一致。首批测试覆盖MIDI36..84，
实体键盘48..79落在其中。没有使用过采样，强FM高音仍可能产生混叠。

试听文件位于 `reports/fm1-audio/`：Python参考模型渲染，非FPGA录音、非原厂硬件录音。
所有文件统一加4倍试听增益，没有逐音色归一化；单音、和弦及释音测试未削波。
板上仍保留固定复音余量和安全主音量，避免和弦简单相加溢出。
DX7音色数据本身不包含FM1后级效果参数；板级默认使用本项目自己的FX配置。

还需补齐：Pitch EG；DX LFO速度/延迟/PMS/AMS映射；全局移调；自由运行相位；
非零L4的生命周期；算法4/6跨算子反馈；异常原厂参数的显式兼容策略。
完整128库还应逐音色做参考波形、动态/音域、听音与换音回归。

128库的后续路线是 **Program ID → 索引/SD → 空闲驻留槽 → 原子提交 → NoteOn**。
先预装常用4个，驻留后起音不需要上传程序。当前UART115200装一个音色约728字节请求
加448字节回应，仅串行线时间就约102 ms，不能当作即时Program Change；后续预取/SD
缓存加载器和App选库界面仍需实现。

## 来源、复现与验证

原厂参数来自 [M-VAVE官方fm1_open](https://github.com/m-vave/fm1_open)，固定提交
`4c7496daac04a95ff10d1afdcc8f9ead2dbabc41` 的 `app/fm_factory.inc`。
原始资源Apache-2.0声明、许可证、哈希与修改说明保存在 `assets/fm1/`。
只使用原厂参数，没有引入受设备限制的二进制DSP SDK。DX缩放公式参考
[Google MSFA](https://github.com/google/music-synthesizer-for-android)，保留Apache署名。

运行 `model/run_fm1_all.ps1`、板级 `model/run_validation.ps1` 和 `model/check_host.py`
可复现数值、接口与整机仿真。最新证据见板级 `reports/fm1-verification.json`。
不可使用较早的 `system-verification.json` 哈希来证明本轮修改。
综合只说明能映射和估计资源；50MHz最终时序、严格RTL交付门禁与上板音频验收仍独立记录。
