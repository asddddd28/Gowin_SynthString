# DashboardTelemetry

Pixel-domain UART byte parser. One complete line commits values at LF (key bank writes commit one additional cycle later through registered address/data); invalid length/CR/hex drops the line. Serial input synchronized by existing UartRx. Local trusted TX source: CRC fields are NOT rechecked. 1 s without a recognized frame clears live; no writes to HardwareLab.

Reset is active low where present. Video never backpressures telemetry.

```wavedrom
{"signal": [{"name": "clk", "wave": "p...."}, {"name": "input", "wave": "x=...", "data": ["A"]}, {"name": "registered", "wave": "x.=..", "data": ["A"]}]}
```
