import { useEffect, useState } from "react";
import {
  ArrowDown,
  Check,
  CheckCircle2,
  Download,
  FileInput,
  LoaderCircle,
  Radio,
  SlidersHorizontal,
  Square,
  Upload,
  X,
} from "lucide-react";
import type { Snapshot } from "../types";
import { EFFECTS, fmt, keyName, Act } from "../config";
import { Badge, CardHead, Matrix, Chart } from "../components";
import { calibrationAvailability } from "../calibrationUi";

export function KeyboardPage({
  s,
  act,
  selected,
  setSelected,
  file,
}: {
  s: Snapshot;
  act: Act;
  selected: number;
  setSelected: (i: number) => void;
  file: (kind: string) => void;
}) {
  const [scope, setScope] = useState("all");
  const [press, setPress] = useState(s.profile.press_threshold * 100);
  const [release, setRelease] = useState(s.profile.release_threshold * 100);
  const [effect, setEffect] = useState(s.settings.effect);
  const [direction, setDirection] = useState(s.settings.direction);
  useEffect(() => {
    setPress(s.profile.press_threshold * 100);
    setRelease(s.profile.release_threshold * 100);
  }, [s.profile.press_threshold, s.profile.release_threshold]);
  useEffect(() => {
    setEffect(s.settings.effect);
    setDirection(s.settings.direction);
  }, [s.settings.effect, s.settings.direction]);
  const ready =
    s.connection === "live" &&
    s.board != null &&
    s.now - s.board_updated <= 0.6 &&
    !s.transfer.busy;
  const game = s.board?.mode === 5;
  const cal = s.calibration;
  const targets =
    cal && cal.stage !== "error"
      ? cal.targets
      : scope === "all"
        ? Array.from({ length: 32 }, (_, i) => i)
        : [selected];
  const availability = calibrationAvailability(s, targets);
  const endpoint = s.profile.keys[selected].calibration;
  return (
    <div className="keyboard-layout">
      <div className="stack">
        <section className="card">
          <CardHead
            eyebrow="KEY MATRIX / 4 × 8"
            title="键盘实时状态"
            right={
              <Badge ok={s.keys.every((k) => k.fresh)}>
                {s.keys.filter((k) => k.fresh).length} / 32 在线
              </Badge>
            }
          />
          <Matrix s={s} selected={selected} onSelect={setSelected} />
          <div className="legend">
            <span>
              <i className="green" />
              FPGA 判定按下
            </span>
            <span>
              <i />
              端点归一化深度
            </span>
            <span>点击按键查看原始曲线</span>
          </div>
        </section>
        <section className="card">
          <CardHead
            eyebrow="RAW SIGNAL"
            title={`${keyName(selected)} · 原始信号`}
            right={
              <strong className="adc-number">
                {s.keys[selected].raw ?? "—"}
                <small>ADC</small>
              </strong>
            }
          />
          <Chart s={s} selected={selected} />
          <div className="signal-stats">
            <span>
              松开 <b>{fmt(endpoint?.rest, 1)}</b>
            </span>
            <span>
              到底 <b>{fmt(endpoint?.bottom, 1)}</b>
            </span>
            <span>
              噪声 <b>{fmt(endpoint?.noise, 1)}</b>
            </span>
            <span>
              深度{" "}
              <b>
                {s.keys[selected].depth == null
                  ? "—"
                  : `${fmt(s.keys[selected].depth! * 100, 1)}%`}
              </b>
            </span>
          </div>
        </section>
        <section className="card">
          <CardHead
            eyebrow="LIGHT ENGINE"
            title="让按键拥有自己的光"
            right={<Badge ok={ready}>板上模式 {s.board?.mode ?? "—"}</Badge>}
          />
          <div className="effect-grid">
            {EFFECTS.map(({ mode, name, desc, icon: Icon }) => (
              <button
                key={mode}
                className={`effect-choice ${effect === mode ? "chosen" : ""}`}
                onClick={() => setEffect(mode)}
              >
                <Icon size={22} />
                <span>
                  <strong>{name}</strong>
                  <small>{desc}</small>
                </span>
                {effect === mode && <Check size={16} />}
              </button>
            ))}
          </div>
          <div className="inline-actions">
            <label>
              流水方向
              <select
                value={direction}
                onChange={(e) => setDirection(Number(e.target.value))}
                disabled={effect !== 3}
              >
                <option value={0}>从左到右 →</option>
                <option value={1}>从上到下 ↓</option>
              </select>
            </label>
            <button
              className="primary"
              disabled={!ready || game}
              onClick={() => act({ kind: "effect", mode: effect, direction })}
            >
              <Upload size={16} />
              发送灯效
            </button>
          </div>
          {game && <p className="hint">游戏正在控制灯光，请先结束游戏。</p>}
        </section>
      </div>
      <aside className="stack">
        <section className="card calibration-card">
          <CardHead
            eyebrow="CALIBRATION"
            title="端点校准"
            right={<SlidersHorizontal size={19} />}
          />
          <div className="profile-name">
            <CheckCircle2 size={17} />
            <span>
              {s.profile.name}
              <small>
                {s.profile.keys.filter((k) => k.calibration).length} / 32
                键已配置
              </small>
            </span>
          </div>
          {availability.blocked && (
            <div className="calibration-notice" role="status">
              <p>{availability.blocked}</p>
              {game && (
                <button
                  disabled={!availability.canExitGame}
                  onClick={() => act({ kind: "game_stop" })}
                >
                  <Square size={14} />
                  退出游戏模式
                </button>
              )}
            </div>
          )}
          {cal && (
            <div
              className={`cal-progress ${cal.stage === "error" ? "failed" : ""}`}
              role="status"
            >
              <div className="progress-track">
                <i style={{ width: `${cal.progress * 100}%` }} />
              </div>
              <p>
                {cal.error ||
                  (
                    {
                      rest: "正在采集松开值，请保持按键松开…",
                      ready: "步骤 1 已完成。请点击“记录终点”，再依次按到底。",
                      press: `步骤 2：已完成 ${cal.done.length} / ${cal.targets.length} 键${cal.done.length === cal.targets.length ? "，可以保存并应用。" : "，未完成的键请按到底约 1 秒。"}`,
                    } as Record<string, string>
                  )[cal.stage]}
              </p>
              {cal.stage === "press" && (
                <div className="cal-dots">
                  {cal.targets.map((i) => (
                    <span
                      key={i}
                      className={cal.done.includes(i) ? "done" : ""}
                    >
                      {i + 1}
                    </span>
                  ))}
                </div>
              )}
              <button
                className="text-button"
                onClick={() => act({ kind: "calibration_cancel" })}
              >
                <X size={14} />
                取消本次校准
              </button>
            </div>
          )}
          <label className="field">
            校准范围
            <select
              value={scope}
              onChange={(e) => setScope(e.target.value)}
              disabled={!!cal && cal.stage !== "error"}
            >
              <option value="all">全部 32 键</option>
              <option value="one">
                仅{" "}
                {keyName(
                  cal && cal.stage !== "error" && cal.targets.length === 1
                    ? cal.targets[0]
                    : selected,
                )}
              </option>
            </select>
          </label>
          <div className="cal-step">
            <span>01</span>
            <div>
              <strong>采集松开位置</strong>
              <p>保持目标按键松开，采集 4 秒。</p>
              <button
                disabled={!!availability.startReason}
                title={
                  availability.startReason ||
                  "采集 4 秒松开值；原校准在应用前保持不变"
                }
                onClick={() =>
                  act({
                    kind: "calibration_start",
                    targets,
                  })
                }
              >
                {cal?.stage === "rest" ? (
                  <LoaderCircle size={15} className="spin" />
                ) : (
                  <Radio size={15} />
                )}
                {cal?.stage === "rest"
                  ? "正在采集…"
                  : cal
                    ? "重新采集松开值"
                    : "开始采集"}
              </button>
            </div>
          </div>
          <div className="cal-step">
            <span>02</span>
            <div>
              <strong>记录按到底位置</strong>
              <p>依次按到底约 1 秒后松开，顺序不限。</p>
              <button
                disabled={!!availability.pressReason}
                title={availability.pressReason || "开始记录按到底位置"}
                onClick={() => act({ kind: "calibration_press" })}
              >
                <ArrowDown size={15} />
                记录终点
              </button>
            </div>
          </div>
          <div className="cal-step">
            <span>03</span>
            <div>
              <strong>应用并下发</strong>
              <p>完整确认后一次提交到 FPGA。</p>
              <button
                className="primary"
                disabled={!!availability.applyReason}
                title={availability.applyReason || "保存候选校准并下发到 FPGA"}
                onClick={() => act({ kind: "calibration_apply" })}
              >
                <Check size={15} />
                保存并应用
              </button>
            </div>
          </div>
          <div className="button-row">
            <button onClick={() => file("import")}>
              <FileInput size={15} />
              导入
            </button>
            <button onClick={() => file("export")}>
              <Download size={15} />
              导出
            </button>
          </div>
          <button
            className="wide"
            disabled={!ready || game || !!cal}
            onClick={() => act({ kind: "sync" })}
          >
            <Upload size={15} />
            下发完整校准
          </button>
        </section>
        <section className="card">
          <CardHead title="按键迟滞" />
          <label className="range-label">
            触发阈值<strong>{press.toFixed(0)}%</strong>
          </label>
          <input
            type="range"
            min="1"
            max="100"
            value={press}
            onChange={(e) => setPress(Number(e.target.value))}
          />
          <label className="range-label">
            释放阈值<strong>{release.toFixed(0)}%</strong>
          </label>
          <input
            type="range"
            min="0"
            max="99"
            value={release}
            onChange={(e) => setRelease(Number(e.target.value))}
          />
          <p className="hint">
            释放值应低于触发值。FPGA 使用原始 ADC
            与迟滞判键；深度仅代表相对行程。
          </p>
          <button
            className="wide"
            disabled={!ready || game || !!cal || release >= press}
            onClick={() =>
              act({
                kind: "thresholds",
                press: press / 100,
                release: release / 100,
              })
            }
          >
            应用阈值
          </button>
        </section>
      </aside>
    </div>
  );
}
