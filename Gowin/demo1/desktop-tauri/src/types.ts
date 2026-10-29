export type Profile = {
  mode: string; wave_a: string; wave_b: string;
  ratio: number; depth: number; mod_hz: number; sensitivity: number; gain_a: number; gain_b: number;
  frame_position?: number; attack: number; decay: number; sustain: number; release: number;
  m_attack: number; m_decay: number; m_sustain: number; m_release: number;
};
export type KeyPatch = { name: string; note: number; velocity: number; keycode: number; shortcut: string; synth: Profile };
export type Sound = { wave: string; attack: number; decay: number; sustain: number; release: number; volume: number; output_boost: number };
export type Config = { version: number; keys: KeyPatch[]; sound: Sound; tauri_bindings?: Record<string, number> };
export type StudioState = {
  config: Config; revision: number; online: boolean; connecting: boolean; port: string; synced: number[]; held: number[];
  transfer: string | null; progress: number; total: number; telemetry: null | { voices: number; oscillators: number; clips: number; cycles: number; flags: number };
  message: string; level: string; pcm_available: boolean; active_resource: string | number | null;
  surge: { connected: boolean; patch: string; count: number; message: string };
  live: {enabled:boolean;pending:number[];inflight:number|null;applied:Record<string,Profile>;error:string};
  performance: {transpose:number;velocity:number|null;armed:boolean;channel:number;sustain:boolean;ui_sustain:boolean;volume:number};
  midi: {connected:boolean;name:string|null;message:string};
};
export type MidiPort = {id:number;name:string};
export type Timbre = { id: number; title: string; category: string; description: string; profile: Profile; resource_id: number | null; waveform: number[] | null };
export type Resource = { id: number; title: string; frames: number; resource_id: number; revision: number };
export type PairPreview = { frames: number[][]; first: number; second: number; fraction: number };
export type Snapshot = { patch: string; parameters: Record<string, { value: number; display: string }>; docs: Record<string, unknown> };
export const MODES = ['波表混合', 'FM / PM', 'AM', '环形调制', '采样钢琴'];
export const WAVES = ['正弦', '三角', '锯齿', '方波', '自定义波表'];
export const noteName = (n: number) => n<0||n>127?'超出音域':['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'][n % 12] + (Math.floor(n / 12) - 1);
