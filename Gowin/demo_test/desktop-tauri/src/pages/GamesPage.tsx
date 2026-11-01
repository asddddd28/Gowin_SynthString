import { Gamepad2, Play, Square } from "lucide-react";
import { Props } from "../config";
import { Badge, CardHead, Matrix } from "../components";

const GAME_NAMES = ["未开始", "贪吃蛇", "打地鼠", "钢琴块"];
const GAME_RULES = [
  "",
  "绿色是蛇，红色是苹果。右下角四键控制方向：K23 ↑、K31 ↓、K30 ←、K32 →。每个苹果 +10 分，撞墙或蛇身结束。",
  "60 秒内按下亮起的地鼠。绿色 +10，青色 +20，红色 +30；按空或漏按不扣分，松开后才可再次计分。",
  "上三行显示预告；最底一行 K25–K32 是操作区。按下绿色目标后下移并 +1 分，按错或超时则红闪结束。",
];
export function GamesPage({ s, act }: Props) {
  const g = s.game;
  const fresh =
    ["live", "replay"].includes(s.connection) &&
    !!g &&
    s.now - s.game_updated <= 0.6;
  const can =
    s.connection === "live" &&
    fresh &&
    !!s.board?.configured &&
    !s.transfer.busy &&
    !s.calibration;
  const phases = ["待机", "准备开始", "进行中", "游戏结束", "结算完成"];
  return (
    <>
      <div className="game-choices">
        {[1, 2, 3].map((id) => (
          <section className={`card game-choice game-${id}`} key={id}>
            <div className="game-art">
              {id === 1 ? (
                <div className="snake-art">
                  <i />
                  <i />
                  <i />
                  <i />
                  <i />
                  <b />
                </div>
              ) : id === 2 ? (
                <div className="mole-art">
                  {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((i) => (
                    <i key={i} />
                  ))}
                </div>
              ) : (
                <div className="piano-art">
                  <i />
                  <i />
                  <i />
                  <i />
                </div>
              )}
            </div>
            <span className="eyebrow">GAME 0{id}</span>
            <h3>{GAME_NAMES[id]}</h3>
            <p>
              {
                [
                  "",
                  "方向、节奏与反应",
                  "一分钟的指尖挑战",
                  "跟随光点，准确落键",
                ][id]
              }
            </p>
            <button
              className={
                g?.game === id && s.board?.mode === 5 ? "primary" : "wide"
              }
              disabled={!can}
              onClick={() => act({ kind: "game_start", game: id })}
            >
              <Play size={15} />
              开始游戏
            </button>
          </section>
        ))}
      </div>
      <div className="two-columns">
        <section className="card">
          <CardHead
            eyebrow="FPGA PLAYFIELD"
            title="板上实时画面"
            right={
              <Badge ok={fresh}>
                {fresh ? phases[g?.phase ?? 0] : "等待游戏遥测"}
              </Badge>
            }
          />
          <Matrix s={s} game />
          <p className="hint">
            画面、倒计时和得分来自 FPGA；此处点击格子不会代替实物按键。
          </p>
        </section>
        <section className="card">
          <CardHead
            title={GAME_NAMES[g?.game ?? 0]}
            right={
              <button
                disabled={!can || s.board?.mode !== 5}
                onClick={() => act({ kind: "game_stop" })}
              >
                <Square size={14} />
                结束游戏
              </button>
            }
          />
          <div className="score-row">
            <div>
              <span>本局得分</span>
              <strong>{g?.score ?? "—"}</strong>
            </div>
            <div>
              <span>剩余时间</span>
              <strong>
                {g?.seconds ?? "—"}
                <small>s</small>
              </strong>
            </div>
          </div>
          <p className="game-rule">
            {GAME_RULES[g?.game ?? 0] ||
              "选择一种游戏开始，所有规则和计分均在 FPGA 上运行。"}
          </p>
          {g && g.phase >= 3 && (
            <div className="game-result">
              {
                [
                  "时间到，结算完成",
                  "撞到边界或方向键区域",
                  "撞到蛇身",
                  "按错底行按键",
                  "未在限时内按下",
                  "已结束游戏",
                  "填满活动区域",
                ][g.reason]
              }
            </div>
          )}
          <div className="info-strip">
            <Gamepad2 size={18} />
            <span>关闭 App 后游戏继续。结束游戏恢复所选灯效。</span>
          </div>
        </section>
      </div>
    </>
  );
}
