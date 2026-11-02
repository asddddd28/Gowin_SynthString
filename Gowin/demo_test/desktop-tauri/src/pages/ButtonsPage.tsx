import { CardHead } from "../components";
import type { Snapshot } from "../types";
import "../buttons.css";

const PINS = ["AA19", "AB18", "Y18", "N15", "U17", "P15"];
export function ButtonsPage({ s }: { s: Snapshot }) {
  const { record, fresh } = s.buttons;
  return <>
    <section className="card tactile-panel">
      <CardHead eyebrow="TACTILE / 6 CHANNELS" title="六颗开关，每次按下都看得见"
        right={<span className={`tactile-live ${fresh ? "online" : ""}`}>
          <i />{fresh ? `${s.connection === "replay" ? "回放" : "实时"} · ${s.rates[8]?.toFixed(0) ?? "0"} Hz` : "等待六键数据"}
        </span>} />
      <p className="tactile-intro">从左到右按下 SW1—SW6，观察状态和次数。去抖由 FPGA 完成，可同时按多颗；本页仅显示实物输入。</p>
      <div className="tactile-board">
        {PINS.map((pin, i) => {
          const pressed = fresh && !!((record?.filtered ?? 0) & (1 << i));
          const raw = fresh ? ((record?.raw ?? 0) >> i) & 1 : null;
          return <div key={pin} className={`tactile-key ${pressed ? "pressed" : ""} ${fresh ? "" : "stale"}`}>
            <div className="tactile-key-label"><strong>SW{i + 1}</strong><span>{String(i + 1).padStart(2, "0")}</span></div>
            <div className="tactile-switch" role="img" aria-label={`SW${i + 1} ${!fresh ? "无实时数据" : pressed ? "按下" : "松开"}`}>
              <i className="tactile-leg top" /><i className="tactile-leg bottom" />
              <div className="tactile-case"><i /><i /><i /><i /><div className="tactile-cap" /></div>
            </div>
            <span className="tactile-state">{!fresh ? "未更新" : pressed ? "按下" : "松开"}</span>
            <div className="tactile-count"><b>{record?.presses[i] ?? "—"}</b><small>次按下</small></div>
            <div className="tactile-raw"><i className={raw === 1 ? "high" : ""} />原始电平 {raw ?? "—"}</div>
            <span className="tactile-pin">{pin} · 接口 {8 - i} 脚</span>
          </div>;
        })}
      </div>
      <div className="info-strip"><span>5 ms 独立去抖 · 按下高电平 · 长按不重复计数 · {s.protocol === "hub" ? "综合采集" : "独立调试"}</span></div>
    </section>
    <section className="card">
      <CardHead eyebrow="INPUT DIAGNOSTICS" title="按下、松开与抖动" />
      <table><thead><tr><th>开关</th><th>按下次数</th><th>松开次数</th><th>原始翻转</th><th>去抖状态</th></tr></thead>
        <tbody>{PINS.map((_, i) => <tr key={i}><td>SW{i + 1}</td><td>{record?.presses[i] ?? "—"}</td>
          <td>{record?.releases[i] ?? "—"}</td><td>{record?.edges[i] ?? "—"}</td>
          <td>{!fresh ? "无实时数据" : ((record?.filtered ?? 0) & (1 << i)) ? "按下" : "松开"}</td></tr>)}</tbody>
      </table>
      <p className="tactile-footnote">计数从 FPGA 复位开始，65535 后回到 0。短按可能短于画面刷新间隔，按下次数仍会保留；原始翻转次数也会包含被过滤的机械抖动。断线后保留历史计数并取消高亮。</p>
    </section>
  </>;
}
