import { useEffect, useState } from "react";
import { ArrowDown, AudioLines, Square, Volume2 } from "lucide-react";
import type { Settings } from "../types";
import { NOTES, Props } from "../config";
import { Badge, CardHead, Switch, PadSurface } from "../components";

export function GuitarPage({ s, act }: Props) {
  const enabled = s.settings.guitar_enabled;
  const [volume, setVolume] = useState(s.settings.volume);
  useEffect(() => setVolume(s.settings.volume), [s.settings.volume]);
  const save = (values: Partial<Settings>) =>
    act({ kind: "settings", settings: { ...s.settings, ...values } });
  return (
    <div className="two-columns pads-layout">
      <section className="card guitar-card">
        <CardHead
          eyebrow="SIX STRINGS / FPGA STRUM"
          title="指尖过弦，即刻发声"
          right={
            <Badge ok={s.audio.ready && enabled && s.connection === "live"}>
              {s.connection === "replay"
                ? "历史回放 · 静音"
                : !enabled
                  ? "已静音"
                  : s.audio.ready
                    ? "原生音频就绪"
                    : "音频未就绪"}
            </Badge>
          }
        />
        <PadSurface s={s} guitar />
        <div className="string-stats">
          {NOTES.map((note, i) => (
            <div key={note + i}>
              <span>{note}</span>
              <strong>{s.guitar.counts[i]}</strong>
              <small>次拨弦</small>
            </div>
          ))}
        </div>
      </section>
      <div className="stack">
        <section className="card audio-card">
          <CardHead
            eyebrow="NATIVE AUDIO"
            title="吉他输出"
            right={<Volume2 size={22} />}
          />
          <Switch
            label="启用划弦发声"
            checked={enabled}
            onChange={(v) => save({ guitar_enabled: v })}
          />
          <label className="range-label">
            音量<strong>{Math.round(volume * 100)}%</strong>
          </label>
          <input
            type="range"
            min="0"
            max="100"
            value={volume * 100}
            onChange={(e) => setVolume(Number(e.target.value) / 100)}
            onPointerUp={() => save({ volume })}
            onKeyUp={() => save({ volume })}
            onBlur={() => {
              if (volume !== s.settings.volume) save({ volume });
            }}
          />
          <button className="wide" onClick={() => act({ kind: "panic" })}>
            <Square size={14} />
            立即止音
          </button>
          <div className="audio-device">
            <AudioLines size={20} />
            <span>
              {s.audio.device || "正在初始化音频"}
              <small>
                {s.audio.sample_rate
                  ? `${s.audio.sample_rate / 1000} kHz · ${s.audio.channels} ch · ${s.audio.buffer_frames ? `${s.audio.buffer_frames} frames` : "设备默认缓冲"}`
                  : "等待输出设备"}
              </small>
            </span>
          </div>
          {s.audio.error && <p className="error-text">{s.audio.error}</p>}
        </section>
        <section className="card">
          <CardHead title="如何演奏" />
          <ol className="instructions">
            <li>触摸左或右 Pad，横向划过竖直的弦。</li>
            <li>只有 FPGA 检测到跨弦事件时才发声；落指和停留不会重复弹奏。</li>
            <li>左侧 E2 / A2 / D3，右侧 G3 / B3 / E4。</li>
          </ol>
          <p className="hint">离开此页、断线或历史回放时自动止音。</p>
        </section>
        <section className="card">
          <CardHead title="事件通路" />
          <div className="pipeline">
            <span>FPGA 判弦</span>
            <ArrowDown size={16} />
            <span>Rust 串口线程</span>
            <ArrowDown size={16} />
            <span>原生音频回调</span>
          </div>
          <div className="signal-stats">
            <span>
              事件延迟 <b>{s.guitar.event_age_ms.map((v) => `${Math.round(v)} ms`).join(" / ")}</b>
            </span>
            <span>
              已送音频 <b>{s.audio.played}</b>
            </span>
            <span>
              队列溢出{" "}
              <b>
                {s.guitar.records.reduce(
                  (sum, r) => sum + (r?.dropped ?? 0),
                  0,
                )}
              </b>
            </span>
            <span>
              过期丢弃 <b>{s.guitar.stale_events}</b>
            </span>
            <span>
              音频丢弃 <b>{s.audio.dropped}</b>
            </span>
          </div>
        </section>
      </div>
    </div>
  );
}
