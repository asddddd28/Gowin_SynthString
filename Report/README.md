# 嵌入式设计竞赛 FPGA 赛道报告模板

按项目内《嵌赛报告模板.docx》组织内容，采用 A4 单面排版。

## 填写方法

在 `main.tex` 修改作品名称、队伍编号和队员。所有章节 `.tex` 文件集中在 `chapter/`，文件名前缀 `00` 至 `08` 表示报告顺序（摘要、正文五部分、附录 A 至 C），实际排版顺序由 `main.tex` 中的引用顺序控制，用实际内容替换写作提示。图片放在 `graphics/`，比赛标志为 `graphics/logo.png`。封面顶部标志兼作封面页眉。

常用正文片段集中在 `component.text`：包含单图、并排子图、占位图、三线表、接口表、跨页表、公式、代码、列表、文字引用、脚注、交叉引用和参考文献用法。按需复制某个片段到章节文件，修改内容、图片文件名和唯一标签；不要将整份片段库载入正式报告。该文件保留 `.text` 扩展名，内容为 LaTeX 源码。

采用工程技术报告字体搭配：中文正文小四宋体，1.35 倍行距，首行缩进两个汉字；章标题三号黑体，一级节标题四号黑体，二级及三级节标题小四黑体；图表标题、表格内容和代码使用五号。西文保留 STIX Two Text，数学保留 STIX Two Math。封面保留独立的标题与队伍信息字号。

摘要及正文五部分保留官方全部内容要求、字数上限及图文提示。参考文献限 20 篇，在 `references.bib` 中录入并通过 `\cite{文献键}` 引用。

附录 A 为补充设计资料，附录 B 为关键代码与测试记录，附录 C 为插图目录、表格目录和符号表。图表目录自动生成，符号表手动维护。

## 编译

使用 XeLaTeX 与 Biber：

```powershell
xelatex -interaction=nonstopmode -halt-on-error main.tex
biber main
xelatex -interaction=nonstopmode -halt-on-error main.tex
xelatex -interaction=nonstopmode -halt-on-error main.tex
```

采用 Windows 中文字体配置，正文与标题使用宋体和黑体；STIX2 字体由 TeX Live 提供。其他系统需安装相应字体或调整 `main.tex` 和 `custom.sty` 的字体配置。字体、字号、页边距及页眉集中在 `custom.sty` 设置。

所有页面包含比赛标志页眉。报告不得出现作者的院校、单位、实验室、地址等身份信息，请同时检查图片、截图及代码注释。

本目录为精简后的可编译模板，未包含原模板停用的类文件、样式文件、院校标志、教学代码及任何编译产物。保留官方 Word 模板用于核对内容要求，保留 `LICENSE.md` 作为原模板的许可说明；软件版权署名不会出现在 PDF 内。


