import { Gauge, RotateCcw, X } from "lucide-react";
import { Props } from "../config";
import { Badge, CardHead, Knob } from "../components";

export function EncodersPage({ s, act }: Props) {
  return (
    <>
      <section className="card">
        <CardHead
          eyebrow="QUADRATURE / 5 CHANNELS"
          title="五路旋转编码器"
          right={
            <button onClick={() => act({ kind: "zero_encoders" })}>
              <RotateCcw size={16} />
              显示归零
            </button>
          }
        />
        <div className="encoder-grid">
          {[4, 3, 2, 1, 0].map((i, n) => {
            const e = s.encoders[i];
            return (
              <div key={i} className="encoder-card">
                <Knob e={e} index={n} />
                <div className="encoder-bits">
                  {["A", "B"].map((bit, b) => (
                    <div key={bit}>
                      <span>{bit}</span>
                      <i
                        className={
                          e.fresh && (e.record?.filtered ?? 0) & (1 << (1 - b))
                            ? "on"
                            : ""
                        }
                      />
                      <small>
                        {e.fresh
                          ? ((e.record?.filtered ?? 0) >> (1 - b)) & 1
                          : "—"}
                      </small>
                    </div>
                  ))}
                </div>
                <dl>
                  <div>
                    <dt>正向边沿</dt>
                    <dd>{e.positive}</dd>
                  </div>
                  <div>
                    <dt>反向边沿</dt>
                    <dd>{e.negative}</dd>
                  </div>
                  <div>
                    <dt>非法跳变</dt>
                    <dd className={e.invalid ? "warning" : ""}>{e.invalid}</dd>
                  </div>
                  <div>
                    <dt>数据中断</dt>
                    <dd>{e.discontinuities}</dd>
                  </div>
                </dl>
              </div>
            );
          })}
        </div>
        <div className="info-strip">
          <Gauge size={18} />
          <span>
            按实物从左到右排列 · 4 个有效边沿 = 1 格 ·
            顺时针为正。归零只改变显示位置，不清除 FPGA 计数。
          </span>
        </div>
      </section>
      <section className="card">
        <CardHead title="原始计数与电平" />
        <table>
          <thead>
            <tr>
              <th>实物位置</th>
              <th>通道</th>
              <th>原始 A/B</th>
              <th>滤波 A/B</th>
              <th>Q 净边沿</th>
              <th>P 正向</th>
              <th>N 反向</th>
              <th>X 非法</th>
              <th>状态</th>
            </tr>
          </thead>
          <tbody>
            {[4, 3, 2, 1, 0].map((i, n) => {
              const e = s.encoders[i],
                r = e.record;
              return (
                <tr key={i}>
                  <td>旋钮 {n + 1}</td>
                  <td>E{i + 1}</td>
                  <td>{r ? r.raw.toString(2).padStart(2, "0") : "—"}</td>
                  <td>{r ? r.filtered.toString(2).padStart(2, "0") : "—"}</td>
                  <td>{r?.q ?? "—"}</td>
                  <td>{r?.positive ?? "—"}</td>
                  <td>{r?.negative ?? "—"}</td>
                  <td>{r?.invalid ?? "—"}</td>
                  <td>
                    <Badge ok={e.fresh}>{e.fresh ? "在线" : "等待"}</Badge>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </section>
    </>
  );
}
