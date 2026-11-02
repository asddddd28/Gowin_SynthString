# DashboardVideo

1650x750 raster, 1280x720 active; +HS 1390..1429, +VS 725..729. Three-cycle pixel/sync pipeline. Snapshot all live state on vertical blank to avoid tearing. 64-entry K01 ADC history, one entry per K01 line, rendered at 8 px/sample. 16x16 text cells, 5x7 doubled glyphs. Telemetry/renderer share pixel clock.

Reset is active low where present. Video never backpressures telemetry.

```wavedrom
{"signal": [{"name": "clk", "wave": "p...."}, {"name": "input", "wave": "x=...", "data": ["A"]}, {"name": "registered", "wave": "x.=..", "data": ["A"]}]}
```
