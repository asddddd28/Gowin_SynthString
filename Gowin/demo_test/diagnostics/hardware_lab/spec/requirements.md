# 综合硬件调试设计约定

范围：32键 ADC 与软件校准下发、FPGA 阈值判定、四种响应灯效及连续彩色流水、三个 FPGA 小游戏、六颗轻触开关、五编码器、摇杆、双 MPR121、FPGA 六弦事件。沿用现有引脚、电平和各模块功能；不包含 demo1 音频合成器整机迁移。新增独立 HardwareLab 工程，原调试工程可回退。操作仅写 SRAM。

50 MHz 主时钟，统一上电延迟/异步复位、同步释放。所有物理引脚合并后必须唯一。键盘 ADC 连续扫描，判键独立于遥测；每100ms捕获一个完整扫描快照，K01..K32按顺序传输，期间穿插ACK/状态。触摸仍100kHz双总线独立采集，保持约213Hz实际轮询，T/G心跳每板约10Hz。六键独立5ms连续电平去抖，每100ms报告B1相干快照，计数不受UART反压影响。编码器每100ms报告5路，摇杆50ms报告。所有串口输出改为有反压的字节流，单UART115200 8N1按整行仲裁，换源只发生在LF后。

ACK与真实G划弦事件优先，连续最多3个优先帧后安排一个普通帧；普通源循环公平轮询。每板事件FIFO仍16项，G帧报告溢出。静止遥测预算约9.27kB/s，保留拨弦突发空间。不能以串口反压暂停物理采样、编码器计数或游戏时钟。

新H1能力帧：H1 + capabilities4hex + build4hex + *CRC2hex + CRLF，共15字节，CRC覆盖前10个ASCII字符。capabilities=00FF（keyboard、encoders、joystick、touchpads、guitar、games、RGB、buttons），build=0101。每250ms一次。只有有效H1帧允许App解锁混合协议；旧单功能固件仍受原协议约束。App提供综合总览，各页同时更新；吉他音频仍由串口线程直接提交。混合记录写原始bin，保持所有帧可回放。

连续彩色流水为灯效mode6；mode5保留给小游戏。旧固件不发送mode6。校准/方向映射沿用已保存文件。实板验证需记录所有帧族、错误率、采样率、校准逐条ACK与最终配置，视觉/触摸需用户实际操作验收。

任务 generate / modify / validate。继续使用本机已有 Gowin / xsim；不安装缺失的远程/Python/script技能。单独记录 compile、ast、readability、comment、naming、profile、testbench、toolchain 的实际结果，不将历史严格风格失败隐藏为通过。
