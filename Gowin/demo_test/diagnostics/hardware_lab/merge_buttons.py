"""Retained one-time six-switch integration migration; do not rerun after editing RTL."""
from pathlib import Path
import shutil
import json
import hashlib

ROOT = Path(__file__).resolve().parent
HDMI = ROOT.parent / 'hardware_hdmi'
APP = ROOT.parents[1] / 'desktop-tauri'
BACKUP = ROOT / 'baseline/buttons_merge_20261102'
assert not BACKUP.exists(), 'Never overwrite the pre-merge baseline'
for base, name in ((ROOT, 'hardware_lab'), (HDMI, 'hardware_hdmi')):
    for folder in ('src', 'spec'):
        shutil.copytree(base / folder, BACKUP / name / folder)
    for pattern in ('*.gprj', '*.py', '*.tcl', 'sim/*.v', 'sim/*.prj', 'README.md', 'impl/pnr/*.fs'):
        for path in base.glob(pattern):
            target = BACKUP / name / path.relative_to(base)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
for rel in ('src', 'src-tauri/src', 'src-tauri/tests', 'release/TangHardwareLab.exe'):
    path = APP / rel
    target = BACKUP / 'app' / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_dir():
        shutil.copytree(path, target)
    else:
        shutil.copy2(path, target)
report = ROOT / 'reports/buttons_merge'
report.mkdir(exist_ok=True)
shutil.copy2(ROOT.parent / 'tactile_buttons/reports/app-live.json', report / 'switches_after_repair.json')
(BACKUP / 'sha256.json').write_text(json.dumps({str(p.relative_to(BACKUP)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in BACKUP.rglob('*') if p.is_file()}, indent=2), encoding='utf-8')

def change(path, replacements):
    text = path.read_text(encoding='utf-8')
    for old, new in replacements:
        assert old in text, (path, old)
        text = text.replace(old, new)
    path.write_text(text, encoding='utf-8')

# Keep the validated standalone UART image/source intact. The new report feeds
# the established one-byte ready/valid adapter instead of driving a second UART.
report_text = (ROOT.parent / 'tactile_buttons/src/TactileReport.v').read_text(encoding='utf-8')
report_text = report_text.replace('TactileReport', 'HardwareButtonReport')
report_text = report_text.replace('coherent six-switch snapshots with CRC-protected ASCII UART.', 'coherent B1 snapshots with backpressure on the shared UART.')
report_text = report_text.replace("parameter [31:0] C_REPORT_CYCLES = 32'd1000000, // 二十毫秒快照周期\n    parameter [15:0] C_BAUD_CYCLES = 16'd434 // 五十兆赫兹下的115200串口", "parameter [31:0] C_REPORT_CYCLES = 32'd5000000 // 一百毫秒快照周期")
report_text = report_text.replace('output o_tx // 板载DEBUG发送引脚', 'input i_tx_ready, // 仲裁器确认当前字节\n    output o_tx_valid, // 字节保持至确认\n    output [7:0] o_tx_data // 一行发送期间独占仲裁通道')
report_text = report_text.replace('真实UART停止位完成标志', '字节保持寄存器非空标志').replace('本字节在整个UART忙周期内保持', '本字节在仲裁反压期间保持').replace('等待UART忙的上升和下降，确保没有重复提交或丢失停止位', '等待字节保持器忙的上升和下降，确保反压期间只提交一次')
report_text = report_text.replace('沿用已验证的串口物理发送器；报告器只在空闲时启动。', '适配综合固件的共享串口，忙时仍继续输入采样与计数。')
report_text = report_text.replace('EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES)) Uart_Inst(', 'TelemetryByte Byte_Inst(').replace('.o_busy(flag_busy),.o_tx(o_tx));', '.i_ready(i_tx_ready),.o_busy(flag_busy),.o_valid(o_tx_valid),.o_data(o_tx_data));')
(ROOT / 'src/HardwareButtonReport.v').write_text(report_text, encoding='utf-8')

change(ROOT / 'src/HardwareLab.v', [
    ('C_TOUCH_REPORT=2500000,C_ID_REPORT=12500000,', 'C_TOUCH_REPORT=2500000,C_ID_REPORT=12500000,C_BUTTON_REPORT=5000000,\n    parameter integer C_BUTTON_FILTER=250000,'),
    ('input [1:0] i_irq,', 'input [1:0] i_irq,\n    input [5:0] i_buttons,'),
    ('wire [4:0] valid,ready,priority;', 'wire [5:0] valid,ready,priority;'),
    ('wire [39:0] data;', 'wire [47:0] data;'),
    ('assign priority[4]=0;', 'assign priority[5:4]=0;'),
    ('TelemetryMux #(.C_BAUD(C_UART_CYCLES)) output_mux(', '''HardwareButtons #(.C_STABLE_CYCLES(C_BUTTON_FILTER),.C_REPORT_CYCLES(C_BUTTON_REPORT)) buttons(
 .i_clk(i_clk),.i_rstn(resetn),.i_buttons(i_buttons),
 .i_tx_ready(ready[5]),.o_tx_valid(valid[5]),.o_tx_data(data[47:40]));
TelemetryMux #(.C_BAUD(C_UART_CYCLES),.C_CHANNELS(6)) output_mux('''),
])
change(ROOT / 'src/TelemetryMux.v', [
    ('五路整行仲裁', '可配置整行仲裁（1至8路）'),
    ('parameter [15:0] C_BAUD=434', 'parameter [15:0] C_BAUD=434,\n    parameter integer C_CHANNELS=5'),
    ('[4:0]', '[C_CHANNELS-1:0]'), ('[39:0]', '[C_CHANNELS*8-1:0]'),
    ('offset<5', 'offset<C_CHANNELS'), ('candidate>=5', 'candidate>=C_CHANNELS'),
    ('candidate=candidate-5', 'candidate=candidate-C_CHANNELS'),
    ('selected==4', 'selected==C_CHANNELS-1'),
])
body = b'H100FF0101'
crc = 0
for byte in body:
    crc ^= byte
    for _ in range(8): crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
crc_text = f'{crc:02X}'
change(ROOT / 'src/HardwareIdentity.v', [
    ('4:data_o="7"', '4:data_o="F"'), ('9:data_o="0"', '9:data_o="1"'),
    ('11:data_o="6";12:data_o="6";', f'11:data_o="{crc_text[0]}";12:data_o="{crc_text[1]}";'),
])
change(HDMI / 'src/HardwareHdmi.v', [
    ('inout [1:0] io_scl, io_sda,', 'input [5:0] i_buttons,\n    inout [1:0] io_scl, io_sda,'),
    ('.i_irq(i_irq),', '.i_irq(i_irq),.i_buttons(i_buttons),'),
])
pins = (ROOT.parent / 'tactile_buttons/src/buttons.cst').read_text(encoding='utf-8').split('IO_LOC "i_buttons[0]"')[1]
pins = '\n// Six active-high tactile inputs, weak pulldowns. SW2 is AB18, NOT TP2 SCL AA18.\nIO_LOC "i_buttons[0]"' + pins
for project, rel, cst in ((ROOT, '', 'hardware'), (HDMI, '../hardware_lab/', 'hdmi')):
    for mod in ('HardwareButtons', 'HardwareButtonReport'):
        change(project / f'{project.name}.gprj', [('<FileList>', f'<FileList>\n<File path="{rel}src/{mod}.v" type="file.verilog" enable="1"/>')])
    change(project / f'{project.name}.gprj', [('<FileList>', '<FileList>\n<File path="../tactile_buttons/src/TactileInput.v" type="file.verilog" enable="1"/>')])
    path = project / f'src/{cst}.cst'
    path.write_text(path.read_text(encoding='utf-8') + pins, encoding='utf-8')

change(APP / 'src-tauri/src/protocol.rs', [('capabilities != 127', '!matches!(capabilities, 127 | 255)')])
change(APP / 'src-tauri/src/model.rs', [
    ('self.view.identity = Some(r);\n                self.view.identity_updated = now;\n                if self.view.protocol != "hub" {\n                    self.log("ok", "已识别综合硬件固件 · H1 / 0x007F", now);\n                }',
     'if self.view.protocol != "hub" {\n                    self.log("ok", &format!("已识别综合硬件固件 · H1 / 0x{:04X}", r.capabilities), now);\n                }\n                self.view.identity = Some(r);\n                self.view.identity_updated = now;'),
])
change(APP / 'src/config.ts', [('s?.buttons.record ? 46 : 40', '(s?.identity && (s.identity.capabilities & 0x80)) || s?.buttons.record ? 46 : 40')])
change(APP / 'src/pages/ButtonsPage.tsx', [('长按不重复计数 · RGB 本轮关闭', '长按不重复计数 · {s.protocol === "hub" ? "综合采集" : "独立调试"}')])
print('Identity:', (body + f'*{crc_text}\r\n'.encode()).decode().strip())
print('Baseline:', BACKUP)
