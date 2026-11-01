import { Settings2 } from "lucide-react";
import { fmt, Props } from "../config";
import { Badge, CardHead, Switch, PadSurface } from "../components";

function PadMappingControls({ s, act }: Props) {
  const save = (key: string, v: boolean) =>
    act({
      kind: "settings",
      settings: { ...s.settings, pad: { ...s.settings.pad, [key]: v } },
    });
  return (
    <section className="card">
      <CardHead title="触摸板方向" right={<Settings2 size={18} />} />
      <Switch
        label="交换左右两块板"
        checked={s.settings.pad.swap_boards}
        onChange={(v) => save("swap_boards", v)}
      />
      <Switch
        label="沿左上至右下对角线翻转"
        checked={s.settings.pad.transpose}
        onChange={(v) => save("transpose", v)}
      />
      <Switch
        label="反转左右"
        checked={s.settings.pad.flip_x}
        onChange={(v) => save("flip_x", v)}
      />
      <Switch
        label="反转上下"
        checked={s.settings.pad.flip_y}
        onChange={(v) => save("flip_y", v)}
      />
      <p className="hint">自动保存显示映射，并同步用于吉他弦号映射。</p>
    </section>
  );
}
export function TouchpadPage({ s, act }: Props) {
  return (
    <>
      <div className="two-columns pads-layout">
        <section className="card">
          <CardHead
            eyebrow="DUAL MPR121 / PCB SCALE"
            title="双板触摸平面"
            right={
              <Badge ok={s.pads.every((p) => p.fresh)}>
                {s.pads.filter((p) => p.fresh).length} / 2 在线
              </Badge>
            }
          />
          <PadSurface s={s} />
          <div className="legend">
            <span>
              <i className="green" />
              有效单指位置
            </span>
            <span>
              <i className="pad-row-color" />R 行电极
            </span>
            <span>
              <i className="pad-column-color" />C 列电极
            </span>
            <span>左右拼接 · 按 PCB 标注比例显示</span>
          </div>
        </section>
        <div className="stack">
          <PadMappingControls s={s} act={act} />
          {s.pads.map((p, i) => (
            <section className="card pad-status" key={i}>
              <CardHead
                title={`TP${i + 1} · ${s.settings.pad.swap_boards ? (i === 0 ? "右侧" : "左侧") : i === 0 ? "左侧" : "右侧"}`}
                right={
                  <Badge ok={p.fresh}>
                    {p.fresh
                      ? "采集中"
                      : p.record
                        ? [
                            "正常",
                            "地址未应答",
                            "总线超时",
                            "配置未应答",
                            "回读不符",
                            "采样未应答",
                            "过流停止",
                            "初始化中",
                          ][p.record.error]
                        : "等待数据"}
                  </Badge>
                }
              />
              <div className="stat-pair">
                <span>
                  采样频率
                  <strong>
                    {p.fresh ? fmt(s.guitar.sample_hz[i], 1) : "—"}{" "}
                    <small>Hz</small>
                  </strong>
                </span>
                <span>
                  触摸位图
                  <strong>
                    {p.record
                      ? `0x${p.record.mask.toString(16).toUpperCase().padStart(3, "0")}`
                      : "—"}
                  </strong>
                </span>
              </div>
              <div
                className="pad-detected"
                aria-label={`TP${i + 1} 已检测电极`}
              >
                {Array.from({ length: 12 }, (_, j) => (
                  <span
                    key={j}
                    className={`${j < 5 ? "row" : "column"} ${p.fresh && Boolean((p.record?.mask ?? 0) & (1 << j)) ? "active" : ""}`}
                  >
                    {j < 5 ? `R${j + 1}` : `C${j - 4}`}
                  </span>
                ))}
              </div>
              <p className="hint">
                位置{" "}
                {p.position
                  ? `${fmt(p.position[0] * 100, 1)}% , ${fmt(p.position[1] * 100, 1)}%`
                  : "无有效触点"}{" "}
                · 地址{" "}
                {p.record
                  ? `0x${p.record.address.toString(16).toUpperCase()}`
                  : "—"}
              </p>
            </section>
          ))}
        </div>
      </div>
      <div className="electrode-grid">
        {s.pads.map((p, i) => (
          <section className="card" key={i}>
            <CardHead
              title={`TP${i + 1} · 电极响应`}
              right={<span className="subtle">BASELINE − FILTERED</span>}
            />
            <div className="electrodes">
              {Array.from({ length: 12 }, (_, j) => (
                <div key={j}>
                  <span className="electrode-track">
                    <i
                      style={{
                        height: `${Math.max(0, Math.min(100, ((p.record?.delta[j] ?? 0) / 80) * 100))}%`,
                      }}
                      className={
                        p.fresh && (p.record?.mask ?? 0) & (1 << j)
                          ? "touched"
                          : ""
                      }
                    />
                  </span>
                  <strong>{p.record?.delta[j] ?? "—"}</strong>
                  <small>
                    {j < 5 ? "R" : "C"}
                    {j < 5 ? j + 1 : j - 4}
                  </small>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    </>
  );
}
