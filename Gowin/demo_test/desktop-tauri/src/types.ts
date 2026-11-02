export type Endpoint = { rest: number; bottom: number; noise: number };
export type Profile = {
  format: string;
  version: number;
  name: string;
  source: string;
  press_threshold: number;
  release_threshold: number;
  keys: { key: number; calibration: Endpoint | null }[];
};
export type Settings = {
  joystick: { swap: boolean; flip_x: boolean; flip_y: boolean };
  pad: {
    swap_boards: boolean;
    transpose: boolean;
    flip_x: boolean;
    flip_y: boolean;
  };
  effect: number;
  direction: number;
  volume: number;
  guitar_enabled: boolean;
};
export type KeyState = {
  raw: number | null;
  filtered: number | null;
  depth: number | null;
  fresh: boolean;
  pressed: boolean;
  updated: number;
};
export type EncoderState = {
  record: {
    channel: number;
    raw: number;
    filtered: number;
    q: number;
    positive: number;
    negative: number;
    invalid: number;
  } | null;
  edges: number;
  positive: number;
  negative: number;
  invalid: number;
  discontinuities: number;
  fresh: boolean;
  updated: number;
  moved: number;
  motion: number;
};
export type PadState = {
  record: {
    board: number;
    sequence: number;
    address: number;
    error: number;
    lines: number;
    mask: number;
    fault: boolean;
    filtered: number[];
    baseline: number[];
    delta: number[];
  } | null;
  position: [number, number] | null;
  fresh: boolean;
  updated: number;
  advanced: number;
};
export type GuitarRecord = {
  board: number;
  packet: number;
  sample: number;
  milliseconds: number;
  flags: number;
  mask: number;
  x: number;
  y: number;
  dropped: number;
};
export type Snapshot = {
  now: number;
  connection: string;
  port: string;
  protocol: string;
  message: string;
  identity: { capabilities: number; build: number } | null;
  identity_updated: number;
  keys: KeyState[];
  encoders: EncoderState[];
  buttons: {
    record: {
      sequence: number; raw: number; filtered: number;
      presses: number[]; releases: number[]; edges: number[];
    } | null;
    fresh: boolean; updated: number;
  };
  joystick: {
    record: {
      sequence: number;
      raw: number;
      filtered: number;
      presses: number;
    } | null;
    x: number | null;
    y: number | null;
    pressed: boolean;
    fresh: boolean;
    updated: number;
  };
  pads: PadState[];
  guitar: {
    records: (GuitarRecord | null)[];
    received: number[];
    sample_hz: number[];
    event_age_ms: number[];
    counts: number[];
    last_hits: number[];
    packet_gaps: number;
    stale_events: number;
    duplicates: number;
  };
  board: {
    seq: number;
    result: number;
    configured: boolean;
    mode: number;
    direction: number;
    generation: number;
    pressed: number;
  } | null;
  board_updated: number;
  game: {
    game: number;
    phase: number;
    seconds: number;
    reason: number;
    score: number;
    misses: number;
    epoch: number;
    colors: number[];
  } | null;
  game_updated: number;
  profile: Profile;
  settings: Settings;
  calibration: {
    stage: string;
    targets: number[];
    done: number[];
    progress: number;
    error: string;
  } | null;
  transfer: {
    busy: boolean;
    completed: number;
    total: number;
    failures: number;
    message: string;
  };
  counts: number[];
  rates: number[];
  rx_bytes: number;
  tx_bytes: number;
  errors: number;
  sequence_errors: number;
  discarded: number;
  fresh_count: number;
  recording: string | null;
  replay_progress: number;
  audio: {
    ready: boolean;
    device: string;
    sample_rate: number;
    channels: number;
    buffer_frames: number;
    error: string;
    played: number;
    dropped: number;
  };
  logs: { time: number; kind: string; text: string }[];
  settings_path: string;
  chart: [number, number][];
};
export type Port = { name: string; description: string; recommended: boolean };
export type Page =
  | "overview"
  | "keyboard"
  | "encoders"
  | "buttons"
  | "joystick"
  | "touchpad"
  | "guitar"
  | "games";
