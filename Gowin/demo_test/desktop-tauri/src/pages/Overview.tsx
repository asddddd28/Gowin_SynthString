import React from "react";
import {
  Activity,
  ArrowRight,
  CheckCircle2,
  ChevronRight,
  Keyboard,
  Touchpad,
} from "lucide-react";
import type { Page, Snapshot } from "../types";
import { EFFECTS, fmt, bytes } from "../config";
import {
  Badge,
  CardHead,
  Metric,
  Matrix,
  Knob,
  JoystickShape,
  PadSurface,
} from "../components";

export function Overview({
  s,
  navigate,
}: {
  s: Snapshot;
  navigate: (p: Page) => void;
}) {
  const live = s.connection === "live";
  const padHz = s.guitar.sample_hz.filter((n) => n > 0);
  const hz = padHz.length ? padHz.reduce((a, b) => a + b) / padHz.length : 0;
  return (
    <>
      <div className="metrics">
        <Metric
          label="实时通道"
          value={String(s.fresh_count)}
          unit="/ 40"
          icon={Activity}
          detail={live ? "32 键 · 5 旋钮 · 摇杆 · 双 Pad" : "等待连接硬件"}
        />
        <Metric
          label="键盘遥测"
          value={fmt(s.rates[0] / 32, 1)}
          unit="Hz"
          icon={Keyboard}
          detail="判键与迟滞由 FPGA 独立运行"
        />
        <Metric
          label="触摸采样"
          value={live ? fmt(hz) : "—"}
          unit="Hz"
          icon={Touchpad}
          detail="来自 FPGA 采样计数 / 时间戳"
        />
        <Metric
          label="帧校验异常"
          value={String(s.errors)}
          icon={CheckCircle2}
          detail={`序号中断 ${s.sequence_errors} · 接收 ${bytes(s.rx_bytes)}`}
        />
      </div>
      <div className="overview-grid">
        <section className="card overview-keyboard">
          <CardHead
            eyebrow="01 / KEYBOARD"
            title="32 个触点，实时回应"
            right={
              <button
                className="text-button"
                onClick={() => navigate("keyboard")}
              >
                键盘与灯效 <ArrowRight size={15} />
              </button>
            }
          />
          <Matrix s={s} onSelect={() => navigate("keyboard")} />
          <div className="card-foot">
            <Badge ok={s.board?.configured && s.now - s.board_updated < 0.6}>
              {s.board?.configured ? "板上校准已生效" : "等待板上校准"}
            </Badge>
            <span>
              {s.keys.filter((k) => k.pressed).length} 键按下 ·{" "}
              {EFFECTS.find((e) => e.mode === s.board?.mode)?.name ??
                (s.board?.mode === 5 ? "小游戏" : "灯效待同步")}
            </span>
          </div>
        </section>
        <section className="dark-card system-card">
          <span className="eyebrow">TANG MEGA 60K</span>
          <h2>硬件就绪状态</h2>
          <div
            className="health-ring"
            style={
              {
                "--progress": `${(s.fresh_count / 40) * 100}%`,
              } as React.CSSProperties
            }
          >
            <div>
              <strong>{s.fresh_count}</strong>
              <span>实时更新 / 40</span>
            </div>
          </div>
          <div className="system-lines">
            <span>
              <i />
              通信协议
              <strong>
                {s.protocol === "hub"
                  ? "H1 · 综合固件"
                  : s.protocol === "unknown"
                    ? "等待识别"
                    : s.protocol.toUpperCase()}
              </strong>
            </span>
            <span>
              <i />
              校准配置
              <strong>
                {s.profile.keys.filter((k) => k.calibration).length} / 32
              </strong>
            </span>
            <span>
              <i />
              串口速率<strong>115200 · 8N1</strong>
            </span>
          </div>
        </section>
        <section
          className="card overview-encoders"
          onDoubleClick={() => navigate("encoders")}
        >
          <CardHead
            eyebrow="02 / ENCODERS"
            title="旋转，精确到每一格"
            right={
              <button
                className="icon-button"
                title="查看编码器"
                onClick={() => navigate("encoders")}
              >
                <ArrowRight size={18} />
              </button>
            }
          />
          <div className="knob-strip">
            {[4, 3, 2, 1, 0].map((i, n) => (
              <div key={i}>
                <Knob e={s.encoders[i]} index={n} mini />
                <strong>{fmt(s.encoders[i].edges / 4, 2)}</strong>
                <small>旋钮 {n + 1}</small>
              </div>
            ))}
          </div>
        </section>
        <section className="card overview-inputs">
          <button onClick={() => navigate("joystick")}>
            <JoystickShape s={s} mini />
            <span>
              <small>03 / JOYSTICK</small>
              <strong>九向摇杆</strong>
              <em>{s.joystick.fresh ? "信号在线" : "等待连接"}</em>
            </span>
            <ChevronRight size={17} />
          </button>
          <button onClick={() => navigate("touchpad")}>
            <div className="mini-pad-wrap">
              <PadSurface s={s} mini />
            </div>
            <span>
              <small>04 / TOUCHPADS</small>
              <strong>双触摸板</strong>
              <em>{s.pads.filter((p) => p.fresh).length} / 2 在线</em>
            </span>
            <ChevronRight size={17} />
          </button>
        </section>
      </div>
      <SessionLog s={s} />
    </>
  );
}
function SessionLog({ s }: { s: Snapshot }) {
  return (
    <section className="card session-log">
      <CardHead
        title="会话动态"
        right={
          <span className="subtle">
            {s.transfer.busy ? "正在等待 FPGA 确认" : "LIVE SESSION"}
          </span>
        }
      />
      {s.logs.length ? (
        s.logs.slice(0, 4).map((l, i) => (
          <div className="log-row" key={`${l.time}-${i}`}>
            <span className={`log-dot ${l.kind}`} />
            <time>+{l.time.toFixed(1)}s</time>
            <span>{l.text}</span>
          </div>
        ))
      ) : (
        <div className="log-row">
          <span className="log-dot" />
          <span>连接板卡后，通信和配置结果将显示在这里。</span>
        </div>
      )}
    </section>
  );
}
