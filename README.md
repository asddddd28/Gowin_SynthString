# Gowin_SynthString

Tang Mega 60K FPGA 合成器与键盘控制 App。此仓库按 2026-10-29 的选择范围导出：**RTL、FS 位流、App 源码及最新 Windows 便携程序**。

## 快速入口

| 内容 | 位置 |
|---|---|
| 合成器 RTL（含 AXIS 候选系统） | [Gowin/demo1/rtl](Gowin/demo1/rtl) |
| 板级顶层与 PLL | [Gowin/demo1/src](Gowin/demo1/src)、[board](Gowin/demo1/board) |
| 合成器 FS | [Gowin/demo1/output](Gowin/demo1/output) 中的 `demo1_pair_31002.fs` / `demo1_pair_31004.fs` |
| Tang Synth Studio：Tauri + Rust | [App 源码及操作说明](Gowin/demo1/desktop-tauri/README.md) |
| Tang Synth Studio Windows 程序 | [完整便携目录](Gowin/demo1/desktop-tauri/release-performance/TangSynthStudio) |
| 旧 Python 合成器界面与协议参考 | [Gowin/demo1/desktop](Gowin/demo1/desktop) |
| 键盘扫描/校准/灯效/游戏 RTL 与 FS | [Gowin/demo_test/diagnostics](Gowin/demo_test/diagnostics) |
| Tang Keyboard Lab | [源码及使用说明](Gowin/demo_test/desktop/README.md) · [最新游戏版便携目录](Gowin/demo_test/desktop/release_games/TangKeyboardLab) |

Windows App 也提供在 [Releases](https://github.com/asddddd28/Gowin_SynthString/releases) 的 ZIP 中。请下载并解压整个目录，保留资源、许可证和 `_internal` 等依赖目录，再运行 EXE。

当前游戏版键盘 App 对应 `Gowin/demo_test/diagnostics/keyboard_games/impl/pnr/keyboard_games.fs`。合成器 App 使用 `demo1_pair_31002/31004.fs`；按真实底板版本选择。现有 FS 来自原项目构建，本次上传未重新综合或烧录。新 AXIS 顶层仍是候选 RTL，不能把已有 FS 视为新 AXIS 系统的位流。

## 上传范围

不包含 `reference`、`material`、原始 88 键 WAV 库、完整备份、安装依赖、虚拟环境、编译缓存、仿真工作目录、工程报告以及历史 App 发布包。保留了 App 构建/运行需要的小型示例音色资源和第三方许可证。

工程部分仅导出 RTL 及关联初始化数据和 FS，不包含原 `.gprj`、CST、SDC 工程约束；如需重新构建硬件，需要从原工作目录补齐匹配的工程和约束。导出的 App 说明中部分历史报告链接可能指向未纳入本次仓库的文件。

`UPLOAD_MANIFEST.json` 列出每个导出文件的原相对路径、大小与 SHA-256。原始工作目录未移动、删除或改写。第三方文件保留各自许可证；本次未另行给整个项目指定统一许可证。
