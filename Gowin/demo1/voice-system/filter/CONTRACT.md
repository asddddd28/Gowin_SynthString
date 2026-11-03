# 全局低通与Cutoff LFO

目标：一个物理双声道低通模块，位于Voice/可选FX混音之后、PCM FIFO之前。左右各有独立两级状态，共用一个乘加器分时计算；12dB/oct低通，无共振。每级系数范围(0,1)，状态更新为z += alpha*(x-z)，任意Cutoff变化仍保持有界。ROM使双级整体在指定Cutoff近似-3dB，不能称为Butterworth。

Cutoff20..18000Hz；系数ROM1024x18，Cutoff对数坐标Q8。全局LFO0.05..20Hz，正弦/三角，深度0..6倍频程，逐音频帧推进，无NoteOn重触发。独立256x16正弦ROM；无需复制现有每声部调制矩阵。控制在FPGA执行，App只发配置。Cutoff一阶平滑约5.24ms；旁路/启用交叉淡化256采样。旁路仍更新滤波状态和LFO，稳态旁路位精确。

模块AxisMasterLowpass使用私有ready/valid音频流（64bit双声道Q26，32bit帧号）与命令流。复用现有AXI-MM命令/完成邮箱，D0原子配置、D1状态；增加独立filter序号，绝不消耗voice/fx序号。D0字0flags(enabled,lfo,triangle)，字1Cutoff对数Q8(0..261888)，字2每样本相位增量(4398..1759219)，字3深度对数Q8(0..160114)，字4非零配置指纹。参数在采样接受时整体快照，不混用新旧配置。D1返回flags/revision/status0/current-cutoff-Q8。AXI读0x64返回LPF1能力，ABI升为1.6。

计算模型在RTL前编写。音频处理目标<48核心时钟/帧，远低于1024帧周期。输入每帧一个脉冲且间隔1024核心时钟；完成队列反压不得停止音频。无更改50MHz、ADC、键盘校准、音色或音频格式。

验证：直流、左右隔离、冲激/扫频幅频响应、快速参数变化、精确旁路、任意输出反压、配置与采样并发；比较Python逐位结果与RTL。整机交错滤波/NoteOn命令、PCM快照、串口重放、上板单音/和弦/LFO扫频以及实际50MHz时序检查。风格矩阵compile/ast/readability/comment/naming/profile/testbench/toolchain分别记录。
