# HardwareHdmi

Unchanged HardwareLab at 50 MHz; reference TMDS_PLL and DVI_TX_Top. Video reset asynchronously asserts on key reset or PLL unlock and releases after 3 pixel clocks. HPD enable stays high. No CPU, DDR or framebuffer.

Reset is active low where present. Video never backpressures telemetry.

```wavedrom
{"signal": [{"name": "clk", "wave": "p...."}, {"name": "input", "wave": "x=...", "data": ["A"]}, {"name": "registered", "wave": "x.=..", "data": ["A"]}]}
```

Vendor DVI reset independently uses the official asynchronous reset: i_rstn AND PLL lock. Pixel dashboard logic retains its three-cycle synchronized reset release.

Six-switch integration: forward new i_buttons[5:0] into HardwareLab. HDMI renderer ignores the B1 line and retains its existing layout; App displays six-switch details. No pixel-domain CDC additions.
