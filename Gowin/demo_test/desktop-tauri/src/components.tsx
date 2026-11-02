import React from "react";
import { Activity } from "lucide-react";
import type { EncoderState, Snapshot } from "./types";
import { NOTES, fmt, keyName } from "./config";

export function Badge({
  ok,
  children,
}: {
  ok?: boolean;
  children: React.ReactNode;
}) {
  return (
    <span className={`badge ${ok ? "good" : ""}`}>
      <span className="dot" />
      {children}
    </span>
  );
}
export function CardHead({
  eyebrow,
  title,
  right,
}: {
  eyebrow?: string;
  title: string;
  right?: React.ReactNode;
}) {
  return (
    <div className="card-head">
      <div>
        {eyebrow && <span className="eyebrow">{eyebrow}</span>}
        <h3>{title}</h3>
      </div>
      {right}
    </div>
  );
}
export function Switch({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
}) {
  return (
    <label className="switch-row">
      <span>{label}</span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
      />
      <i />
    </label>
  );
}
export function Metric({
  label,
  value,
  unit,
  icon: Icon,
  detail,
}: {
  label: string;
  value: string;
  unit?: string;
  icon: typeof Activity;
  detail: string;
}) {
  return (
    <div className="metric">
      <div className="metric-label">
        {label}
        <Icon size={17} />
      </div>
      <div className="metric-value">
        {value}
        <small>{unit}</small>
      </div>
      <p>{detail}</p>
    </div>
  );
}
export function Matrix({
  s,
  selected,
  onSelect,
  compact = false,
  game = false,
}: {
  s: Snapshot;
  selected?: number;
  onSelect?: (i: number) => void;
  compact?: boolean;
  game?: boolean;
}) {
  const gameFresh =
    ["live", "replay"].includes(s.connection) && s.now - s.game_updated <= 0.6;
  return (
    <div
      className={`keyboard-matrix ${compact ? "compact" : ""} ${game ? "game-matrix" : ""}`}
    >
      {s.keys.map((k, i) => {
        const color = game && gameFresh ? (s.game?.colors[i] ?? 0) : 0;
        return (
          <button
            type="button"
            key={i}
            title={`${keyName(i)} · ADC ${k.raw ?? "—"}`}
            className={`keycap ${!k.fresh ? "stale" : ""} ${k.pressed && !game ? "pressed" : ""} ${selected === i ? "selected" : ""} pixel-${color}`}
            onClick={() => onSelect?.(i)}
            style={
              { "--depth": `${(k.depth ?? 0) * 100}%` } as React.CSSProperties
            }
          >
            <span className="key-id">{keyName(i)}</span>
            <strong>
              {game
                ? s.game?.game === 1
                  ? ((
                      { 22: "↑", 30: "↓", 29: "←", 31: "→" } as Record<
                        number,
                        string
                      >
                    )[i] ?? "")
                  : color
                    ? "●"
                    : ""
                : compact
                  ? k.pressed
                    ? "●"
                    : ""
                  : (k.raw ?? "—")}
            </strong>
            {!compact && !game && (
              <span className="key-depth">
                {k.depth == null ? "待校准" : `${Math.round(k.depth * 100)}%`}
              </span>
            )}
            <i className="key-fill" />
          </button>
        );
      })}
    </div>
  );
}
export function Chart({ s, selected }: { s: Snapshot; selected: number }) {
  const values = s.chart;
  const p = s.profile.keys[selected].calibration;
  const raw = values.map((v) => v[1]);
  const min = Math.min(...raw, ...(p ? [p.rest, p.bottom] : [0]));
  const max = Math.max(...raw, ...(p ? [p.rest, p.bottom] : [4095]));
  const span = Math.max(100, max - min);
  const y = (v: number) => 146 - ((v - min) / span) * 126;
  const points = values
    .map(
      (v, i) => `${20 + (i / Math.max(1, values.length - 1)) * 740},${y(v[1])}`,
    )
    .join(" ");
  return (
    <div className="chart">
      <svg
        viewBox="0 0 780 172"
        role="img"
        aria-label={`${keyName(selected)} 最近原始 ADC 曲线`}
      >
        <defs>
          <linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#3d9272" stopOpacity=".18" />
            <stop offset="100%" stopColor="#3d9272" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[20, 62, 104, 146].map((v) => (
          <line key={v} x1="20" x2="760" y1={v} y2={v} stroke="#e7eae4" />
        ))}
        {p &&
          [
            p.rest + (p.bottom - p.rest) * s.profile.press_threshold,
            p.rest + (p.bottom - p.rest) * s.profile.release_threshold,
          ].map((v, i) => (
            <line
              key={i}
              x1="20"
              x2="760"
              y1={y(v)}
              y2={y(v)}
              stroke={i ? "#bdc8bd" : "#e4af67"}
              strokeDasharray="5 5"
            />
          ))}
        {values.length > 1 && (
          <>
            <polygon
              points={`20,160 ${points} 760,160`}
              fill="url(#chartFill)"
            />
            <polyline
              points={points}
              fill="none"
              stroke="#287d5b"
              strokeWidth="2.2"
              strokeLinejoin="round"
            />
          </>
        )}
        <text x="20" y="170" fill="#8b938a" fontSize="10">
          最近{" "}
          {values.length
            ? fmt(values[values.length - 1][0] - values[0][0], 1)
            : "0"}{" "}
          秒
        </text>
        <text x="760" y="170" textAnchor="end" fill="#8b938a" fontSize="10">
          NOW
        </text>
      </svg>
      {values.length === 0 && (
        <div className="chart-empty">连接后显示真实 ADC 曲线</div>
      )}
    </div>
  );
}
export function Knob({
  e,
  index,
  mini = false,
}: {
  e: EncoderState;
  index: number;
  mini?: boolean;
}) {
  return (
    <div
      className={`knob-module ${mini ? "mini" : ""} ${!e.fresh ? "inactive" : ""}`}
    >
      <div className="knob-ring">
        <div className="knob-ticks" />
        <div
          className="knob"
          style={{ transform: `rotate(${(e.edges / 4) * 18}deg)` }}
        >
          <i />
        </div>
        {!mini && <span className="knob-zero" />}
      </div>
      {!mini && (
        <>
          <div className="knob-name">
            旋钮 {index + 1}
            <span>E{5 - index}</span>
          </div>
          <div className="knob-number">
            {fmt(e.edges / 4, 2)}
            <small>格</small>
          </div>
          <span className={`motion ${e.motion ? "moving" : ""}`}>
            {!e.fresh
              ? "等待数据"
              : e.motion === 1
                ? "顺时针 ↻"
                : e.motion === -1
                  ? "逆时针 ↺"
                  : e.motion === 2
                    ? "往返 / 抖动"
                    : "静止"}
          </span>
        </>
      )}
    </div>
  );
}
export function JoystickShape({
  s,
  mini = false,
}: {
  s: Snapshot;
  mini?: boolean;
}) {
  const j = s.joystick;
  const x = j.fresh ? (j.x ?? 0) : 0;
  const y = j.fresh ? (j.y ?? 0) : 0;
  return (
    <div
      className={`joystick-shape ${mini ? "mini" : ""} ${j.pressed ? "held" : ""} ${!j.fresh ? "inactive" : ""}`}
    >
      <div className="joy-cross horizontal" />
      <div className="joy-cross vertical" />
      <div className="joy-outer" />
      <div className="joy-base" />
      <span className={`joy-label north ${y < 0 ? "lit" : ""}`}>上</span>
      <span className={`joy-label south ${y > 0 ? "lit" : ""}`}>下</span>
      <span className={`joy-label west ${x < 0 ? "lit" : ""}`}>左</span>
      <span className={`joy-label east ${x > 0 ? "lit" : ""}`}>右</span>
      <div
        className="joy-stem"
        style={{ transform: `translate(${x * 30}%,${y * 30}%)` }}
      />
      <div
        className="joy-ball"
        style={{
          transform: `translate(${x * 42}%,${y * 42}%) scale(${j.pressed ? 0.92 : 1})`,
        }}
      >
        <span />
        <i />
      </div>
    </div>
  );
}
export function PadSurface({
  s,
  guitar = false,
  mini = false,
}: {
  s: Snapshot;
  guitar?: boolean;
  mini?: boolean;
}) {
  return (
    <div
      className={`pad-assembly ${guitar ? "guitar-surface" : ""} ${mini ? "mini" : ""}`}
    >
      {[0, 1].map((side) => {
        const board = s.settings.pad.swap_boards ? 1 - side : side;
        const p = s.pads[board];
        return (
          <div key={side} className={`pad-surface ${p.fresh ? "online" : ""}`}>
            <div className="pad-corner tl" />
            <div className="pad-corner tr" />
            <div className="pad-corner bl" />
            <div className="pad-corner br" />
            <div className="pad-caption">
              <span>TP{board + 1}</span>
              <span>{p.fresh ? "LIVE" : "OFFLINE"}</span>
            </div>
            {guitar ? (
              [0, 1, 2].map((slot) => {
                const string = side * 3 + slot;
                const hit =
                  s.guitar.last_hits[string] > 0 &&
                  s.now - s.guitar.last_hits[string] < 0.3 &&
                  s.connection === "live";
                return (
                  <div
                    key={slot}
                    className={`guitar-string ${hit ? "plucked" : ""}`}
                    style={
                      {
                        left: `${6 + (slot + 1) * 22}%`,
                        "--weight": `${3.3 - string * 0.35}px`,
                      } as React.CSSProperties
                    }
                  >
                    <span className="string-pin" />
                    <i />
                    <span className="string-note">
                      {NOTES[string]}
                      <small>{string + 1}</small>
                    </span>
                  </div>
                );
              })
            ) : (
              <>
                <div className="pad-grid" />
                <div
                  className="pad-electrode-overlay"
                  aria-label={`TP${board + 1} 检测到的行列`}
                >
                  {Array.from({ length: 12 }, (_, electrode) => {
                    const row = electrode < 5;
                    const index = row ? electrode : electrode - 5;
                    const count = row ? 5 : 7;
                    const vertical = row === s.settings.pad.transpose;
                    const flipped = vertical
                      ? s.settings.pad.flip_x
                      : s.settings.pad.flip_y;
                    const position =
                      (flipped ? count - 1 - index : index) / (count - 1);
                    const halfWidth = 0.36 / (count - 1);
                    const start = Math.max(0, position - halfWidth) * 100;
                    const end = Math.min(1, position + halfWidth) * 100;
                    const active =
                      p.fresh &&
                      Boolean((p.record?.mask ?? 0) & (1 << electrode));
                    const label = `${row ? "R" : "C"}${index + 1}`;
                    return (
                      <div
                        key={electrode}
                        className={`pad-electrode ${row ? "row" : "column"} ${vertical ? "vertical" : "horizontal"} ${active ? "active" : ""}`}
                        style={
                          vertical
                            ? { left: `${start}%`, width: `${end - start}%` }
                            : { top: `${start}%`, height: `${end - start}%` }
                        }
                        aria-label={`${label}${active ? " 已检测" : " 未检测"}`}
                      >
                        <span>{label}</span>
                      </div>
                    );
                  })}
                </div>
                <div className="pad-center-mark">
                  <span />
                  <i />
                </div>
              </>
            )}
            {p.fresh && p.position && (
              <div
                className="finger"
                style={{
                  left: `${6 + p.position[0] * 88}%`,
                  top: `${8 + p.position[1] * 80}%`,
                }}
              >
                <i />
                <span />
              </div>
            )}
            {!mini && !guitar && (
              <span className="pad-dimension">43.596 × 61.976 mm</span>
            )}
          </div>
        );
      })}
      {!mini && (
        <div className="dimension-line">
          <i />
          <span>90.832 mm</span>
          <i />
        </div>
      )}
    </div>
  );
}
