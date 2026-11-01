# FPGA 六弦检测合同

本轮为 generate / modify / validate。沿用本机已经用于此板的 Gowin / xsim 工具链，不配置远程服务器，也不安装缺失的远程技能。技能附加的 Python / script 生成器未安装。质量矩阵分别记录 compile、ast、readability、comment、naming、profile、testbench、toolchain，不把功能仿真当作严格风格检查通过。

保留旧 touchpad 工程，新工程只写 SRAM。50 MHz、低有效复位；两块 MPR121 独立连续读取，100 kHz I²C 先实测可靠性。0x5D 从 0x24 改为 0x20：CDT 不变、ESI 1 ms、SFI 4；触发/释放仍 12/6。配置回读每 128 个采样执行一次，异常立即撤销轨迹并重试。完整读取 42 字节后一次性提交 FPGA 快照，但这不代表芯片所有电极严格同时更新。

GuitarTracker 在每次新快照后顺序计算两轴加权中心。只接受单一连续触摸簇，初次接触、释放、错误、超时不产生事件。两轴都检测三条 25/50/75% 弦线，固定点滞回 20/1024，每弦 12 ms 再触发间隔；单次跨越多根弦全部发出位图。两轴均在硬件判定，App 仅按既有 transpose/flip/swap 映射挑选弦，不再次判定轨迹。

每板 16 项事件 FIFO，溢出计数可见。UART 115200 8N1，事件优先于后续遥测，不能截断在途帧；左右公平仲裁。T 原始遥测保持兼容。G1 协议共 37 字节：G1、板号、包序号4hex、采样序号4hex、毫秒时间8hex、flags1hex、两轴事件位图2hex、X3hex、Y3hex、溢出计数4hex、*CRC2hex、CRLF。flags bit0=contact，bit1=sensor healthy，bit2=X right，bit3=Y down；mask低3位X、高3位Y。坐标X为5电极轴，Y为7电极轴，已对应默认对角镜像。无事件的周期 G 帧表示能力及当前状态。

App 串口线程直接解析 G 帧和提交音频，Tk 仅显示。旧固件不再由软件模拟划弦；界面提示需要 FPGA 划弦固件。验证包括落点静止、多弦跨越、反向、滞回、断触、错误、两板同时事件、CRC、FIFO 溢出、优先级及旧协议兼容。
