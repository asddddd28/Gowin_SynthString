# UI 资源与第三方许可

本应用的界面布局、波形/包络 SVG、音色卡片和应用标志为工程内实现。没有下载音乐专辑封面或使用来源不明的付费模板。UI 字体与图标随应用打包，运行时不依赖外部 CDN。

| 资源 | 用途 | 许可 / 来源 |
| --- | --- | --- |
| Tauri 2 | 原生桌面壳、IPC、WebView2 | MIT / Apache-2.0；[官方文档](https://v2.tauri.app/) |
| React | 组件与状态 | MIT；[React](https://react.dev/) |
| Radix Primitives | 可访问滑杆、开关、对话框与焦点管理 | MIT；[Slider 文档](https://www.radix-ui.com/primitives/docs/components/slider) |
| Lucide | 统一线性 SVG 图标 | ISC，部分源于 Feather；[完整许可](https://lucide.dev/license) |
| Geist Variable | 拉丁文字体，中文回退到系统微软雅黑 | OFL-1.1；[Geist](https://github.com/vercel/geist-font) |
| JetBrains Mono Variable | 参数、音高与数字等宽字体 | OFL-1.1；[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) |
| shadcn/ui Music 示例 | 参考侧栏、资源浏览和组件分层方式；没有复制其页面源码、封面或模板文件 | [官方 Music 示例](https://v3.shadcn.com/examples/music)、[组件文档](https://ui.shadcn.com/docs/components/radix/slider) |
| serialport-rs | Rust 串口读写与设备枚举 | MPL-2.0；[官方仓库](https://github.com/serialport/serialport-rs)；未修改上游源文件 |
| midir | Rust 原生 MIDI 输入、设备枚举与连接 | MIT；[官方文档](https://docs.rs/midir/0.11.1/midir/)；未修改上游源文件 |
| WAI-ARIA Slider Pattern | 旋钮的滑杆语义、数值和键盘交互参考；SVG 旋钮为本项目实现 | [W3C 交互规范](https://www.w3.org/WAI/ARIA/apg/patterns/slider/) |
| serde_json / sha2 / crc32fast / chrono / windows-sys | 配置、资源校验、时间和 Windows 音频 API | 实际版本和许可详见 `licenses/rust-crates.json` 与随附原文 |
| AKWF 基础素材 | 随附单周期基础音色 | CC0；原文件信息、SHA256 与许可保留于 `assets/basic_bank/SOURCES.JSN`、`LICENSE.md` |

便携包的 `licenses/` 由构建脚本从实际 JavaScript 包和 Rust crate 收集许可原文（源码目录生成于 `licenses-native/`）；字体、Lucide 的完整许可应随目录保留。完整 JavaScript 版本锁定在 `package-lock.json`，Rust 依赖锁定在 `src-tauri/Cargo.lock`。`rust-crates.json` 记录所有已解析 crate 的版本、许可与源。

0.4.0 继续使用 [Tauri Rust commands](https://v2.tauri.app/develop/calling-rust/) 直接调用主进程内的 Rust 后台，不开放额外的 HTTP 服务端口。旧 Python/PyInstaller 后台不再随新包分发。Windows 参考试听使用系统 PlaySoundW；源代码与包均保留原音色素材出处。
