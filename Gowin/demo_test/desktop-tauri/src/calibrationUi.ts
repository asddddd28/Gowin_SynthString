import type { Snapshot } from "./types";

/** Explain the actual gate instead of presenting an unexplained disabled button. */
export function calibrationAvailability(s: Snapshot, targets: number[]) {
  let connectionReason = "";
  if (s.connection === "replay" || s.connection === "replay_done")
    connectionReason = "正在回放历史数据；请连接实时板卡后校准。";
  else if (s.connection !== "live")
    connectionReason = "请先连接实时板卡，等待键盘数据更新。";
  else if (!s.board || s.now - s.board_updated > 0.6)
    connectionReason = "尚未收到有效的板卡状态，请检查固件与串口连接。";
  else if (s.transfer.busy)
    connectionReason = `正在等待板卡确认（${s.transfer.completed}/${s.transfer.total}），完成后即可继续。`;

  const game = s.board?.mode === 5;
  const missing = targets.filter((i) => !s.keys[i]?.fresh);
  const blocked =
    connectionReason ||
    (game
      ? "板卡仍处于小游戏模式。即使本局已结束，也需退出游戏模式才能校准。"
      : missing.length
        ? `有 ${missing.length} 个目标按键的数据未更新，请等待实时数据。`
        : "");
  const c = s.calibration;
  const startReason =
    blocked ||
    (c?.stage === "rest" ? "正在采集松开位置，请保持按键松开。" : "");
  const pressReason =
    blocked || (c?.stage === "ready" ? "" : "请先完成步骤 1 的松开位置采集。");
  const applyReason =
    blocked ||
    (c?.stage !== "press"
      ? "请先开始步骤 2，并采集目标按键的到底位置。"
      : c.done.length !== c.targets.length
        ? `还有 ${c.targets.length - c.done.length} 个按键未采到有效终点。`
        : "");
  return {
    game,
    blocked,
    startReason,
    pressReason,
    applyReason,
    canExitGame: game && !connectionReason,
  };
}
