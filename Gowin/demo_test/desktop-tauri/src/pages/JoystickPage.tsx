import React from "react";
import { MousePointer2, Settings2, X } from "lucide-react";
import { Props } from "../config";
import { Badge, CardHead, Switch, JoystickShape } from "../components";

export function JoystickPage({ s, act }: Props) {
  const j = s.joystick;
  const direction = !j.fresh
    ? "等待连接"
    : j.x == null || j.y == null
      ? "电平组合异常"
      : j.x === 0 && j.y === 0
        ? "中心"
        : `${j.y === -1 ? "上" : j.y === 1 ? "下" : ""}${j.x === -1 ? "左" : j.x === 1 ? "右" : ""}`;
  const save = (key: string, v: boolean) =>
    act({
      kind: "settings",
      settings: {
        ...s.settings,
        joystick: { ...s.settings.joystick, [key]: v },
      },
    });
  return (
    <div className="two-columns">
      <section className="card joystick-card">
        <CardHead
          eyebrow="DIGITAL JOYSTICK"
          title="方向与按压"
          right={
            <Badge ok={j.fresh}>{j.fresh ? "实时连接" : "等待数据"}</Badge>
          }
        />
        <JoystickShape s={s} />
        <div className="joy-readout">
          <strong>{direction}</strong>
          <Badge ok={j.pressed}>{j.pressed ? "SW 按下" : "SW 松开"}</Badge>
        </div>
        <p className="center-hint">九向离散状态 · 图示位移不代表模拟行程</p>
      </section>
      <div className="stack">
        <section className="card">
          <CardHead title="按压计数" right={<MousePointer2 size={20} />} />
          <div className="big-number">
            {j.record?.presses ?? "—"}
            <small>次</small>
          </div>
          <p className="hint">来自 FPGA 累计计数，SW 低电平有效。</p>
        </section>
        <section className="card">
          <CardHead title="显示方向" right={<Settings2 size={18} />} />
          <Switch
            label="交换 X / Y"
            checked={s.settings.joystick.swap}
            onChange={(v) => save("swap", v)}
          />
          <Switch
            label="反转左右"
            checked={s.settings.joystick.flip_x}
            onChange={(v) => save("flip_x", v)}
          />
          <Switch
            label="反转上下"
            checked={s.settings.joystick.flip_y}
            onChange={(v) => save("flip_y", v)}
          />
        </section>
        <section className="card">
          <CardHead title="数字输入" />
          <div className="signal-table">
            <span />
            <span>原始</span>
            <span>去抖</span>
            {["XH", "XL", "YH", "YL", "SW"].map((name, i) => (
              <React.Fragment key={name}>
                <strong>{name}</strong>
                {[j.record?.raw, j.record?.filtered].map((value, n) => (
                  <span
                    key={n}
                    className={
                      j.fresh && value != null && value & (1 << i)
                        ? "signal-high"
                        : ""
                    }
                  >
                    {j.fresh && value != null ? (value >> i) & 1 : "—"}
                  </span>
                ))}
              </React.Fragment>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
