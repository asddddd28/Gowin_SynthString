import {
  Activity,
  AudioLines,
  Gamepad2,
  Gauge,
  Guitar,
  Keyboard,
  LayoutDashboard,
  Move,
  Power,
  Radio,
  Sparkles,
  Touchpad,
  Zap,
} from "lucide-react";
import type { Page, Snapshot } from "./types";

export const NAV: {
  id: Page;
  title: string;
  en: string;
  icon: typeof Activity;
}[] = [
  { id: "overview", title: "硬件总览", en: "OVERVIEW", icon: LayoutDashboard },
  { id: "keyboard", title: "键盘与灯效", en: "KEYBOARD", icon: Keyboard },
  { id: "encoders", title: "旋转编码器", en: "ENCODERS", icon: Gauge },
  { id: "buttons", title: "六键开关", en: "SWITCHES", icon: Power },
  { id: "joystick", title: "摇杆", en: "JOYSTICK", icon: Move },
  { id: "touchpad", title: "双触摸板", en: "TOUCHPADS", icon: Touchpad },
  { id: "guitar", title: "吉他模拟器", en: "GUITAR", icon: Guitar },
  { id: "games", title: "小游戏", en: "PLAYGROUND", icon: Gamepad2 },
];
export const EFFECTS = [
  { mode: 0, name: "关闭灯光", desc: "停止普通灯效", icon: Power },
  { mode: 1, name: "单键余辉", desc: "独立亮起 · 约 1 秒", icon: Sparkles },
  { mode: 2, name: "彩色涟漪", desc: "由触点向四周扩散", icon: Radio },
  { mode: 3, name: "快速流水", desc: "整板扫过 · 可选方向", icon: Zap },
  { mode: 4, name: "十字扩散", desc: "沿行列向外扩散", icon: Move },
  { mode: 6, name: "连续彩色流水", desc: "四行持续渐变流动", icon: AudioLines },
];
export const NOTES = ["E2", "A2", "D3", "G3", "B3", "E4"];
export const inputCapacity = (s: Snapshot | null) =>
  s?.protocol === "buttons" ? 6 : (s?.identity && (s.identity.capabilities & 0x80)) || s?.buttons.record ? 46 : 40;
export const fmt = (v: number | undefined | null, d = 0) =>
  v == null ? "—" : v.toFixed(d);
export const keyName = (n: number) => `K${String(n + 1).padStart(2, "0")}`;
export const bytes = (n: number) =>
  n < 1024 ? `${n} B` : `${(n / 1024).toFixed(1)} KB`;
export type Act = (action: Record<string, unknown>) => Promise<void>;
export type Props = { s: Snapshot; act: Act };
