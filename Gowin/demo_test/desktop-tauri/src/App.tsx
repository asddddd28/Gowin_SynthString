import { useCallback, useEffect, useRef, useState } from "react";
import {
  Check,
  CheckCircle2,
  ChevronUp,
  ChevronDown,
  ChevronRight,
  Circle,
  Command,
  Download,
  LoaderCircle,
  Play,
  Plug,
  Power,
  RefreshCw,
  Settings2,
  Square,
  WifiOff,
  X,
} from "lucide-react";
import type { Page, Port, Snapshot } from "./types";
import { NAV, bytes, Act } from "./config";

import { invoke } from "@tauri-apps/api/core";
import { Overview } from "./pages/Overview";
import { KeyboardPage } from "./pages/KeyboardPage";
import { EncodersPage } from "./pages/EncodersPage";
import { JoystickPage } from "./pages/JoystickPage";
import { TouchpadPage } from "./pages/TouchpadPage";
import { GuitarPage } from "./pages/GuitarPage";
import { GamesPage } from "./pages/GamesPage";
export default function App() {
  const [s, setS] = useState<Snapshot | null>(null);
  const [page, setPage] = useState<Page>("overview");
  const [selected, setSelected] = useState(0);
  const [ports, setPorts] = useState<Port[]>([]);
  const [port, setPort] = useState("");
  const [notice, setNotice] = useState("");
  const [noticeError, setNoticeError] = useState(false);
  const [working, setWorking] = useState(false);
  const [sessionOpen, setSessionOpen] = useState(false);
  const scrollRef = useRef<HTMLElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const [scroll, setScroll] = useState({
    needed: false,
    top: true,
    bottom: true,
  });
  const updateScroll = useCallback(() => {
    const node = scrollRef.current;
    if (!node) return;
    const next = {
      needed: node.scrollHeight > node.clientHeight + 2,
      top: node.scrollTop <= 2,
      bottom: node.scrollTop + node.clientHeight >= node.scrollHeight - 2,
    };
    setScroll((old) =>
      old.needed === next.needed &&
      old.top === next.top &&
      old.bottom === next.bottom
        ? old
        : next,
    );
  }, []);
  useEffect(() => {
    const observer = new ResizeObserver(updateScroll);
    if (scrollRef.current) observer.observe(scrollRef.current);
    if (contentRef.current) observer.observe(contentRef.current);
    updateScroll();
    return () => observer.disconnect();
  }, [updateScroll]);
  const scrollPage = (direction: number) => {
    const node = scrollRef.current;
    node?.scrollBy({
      top: direction * Math.max(160, node.clientHeight * 0.7),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "instant"
        : "smooth",
    });
  };
  const selectedRef = useRef(selected);
  selectedRef.current = selected;
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const notify = (text: string, error = false) => {
    setNotice(text);
    setNoticeError(error);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setNotice(""), error ? 9000 : 5000);
  };
  const act: Act = async (action) => {
    try {
      const result = await invoke<string>("perform", { action });
      if (!["page", "settings"].includes(String(action.kind))) notify(result);
    } catch (e) {
      notify(String(e), true);
    }
  };
  const file = async (kind: string) => {
    try {
      notify(await invoke<string>("file_action", { kind }));
    } catch (e) {
      notify(String(e), true);
    }
  };
  const refresh = async () => {
    try {
      const p = await invoke<Port[]>("list_ports");
      setPorts(p);
      setPort((current) =>
        p.some((v) => v.name === current)
          ? current
          : (p.find((v) => v.recommended && v.description.includes("B"))
              ?.name ??
            p.find((v) => v.recommended)?.name ??
            p[0]?.name ??
            ""),
      );
    } catch (e) {
      notify(String(e), true);
    }
  };
  useEffect(() => {
    let disposed = false;
    let timer: ReturnType<typeof setTimeout>;
    let failures = 0;
    const poll = async () => {
      try {
        const data = await invoke<Snapshot>("snapshot", {
          selected: selectedRef.current,
        });
        if (!disposed) {
          setS(data);
          failures = 0;
        }
      } catch (e) {
        if (++failures === 1 && !disposed)
          notify(`无法读取原生后端：${e}`, true);
      }
      if (!disposed) timer = setTimeout(poll, 40);
    };
    poll();
    refresh();
    return () => {
      disposed = true;
      clearTimeout(timer);
      if (toastTimer.current) clearTimeout(toastTimer.current);
    };
  }, []);
  const navigate = (next: Page) => {
    setPage(next);
    act({ kind: "page", page: next });
    scrollRef.current?.scrollTo({ top: 0 });
  };
  const connect = async () => {
    setWorking(true);
    await act({
      kind:
        s?.connection === "live" || s?.connection === "connecting"
          ? "disconnect"
          : "connect",
      port,
    });
    setWorking(false);
  };
  const item = NAV.find((n) => n.id === page)!;
  const live = s?.connection === "live";
  const replay = s?.connection === "replay" || s?.connection === "replay_done";
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">
            <i />
            <i />
            <i />
            <i />
          </div>
          <div>
            <strong>
              TANG<span>LAB</span>
            </strong>
            <small>HARDWARE STUDIO</small>
          </div>
        </div>
        <div className="nav-caption">
          工作空间 <span>01</span>
        </div>
        <nav>
          {NAV.map(({ id, title, en, icon: Icon }, i) => (
            <button
              key={id}
              onClick={() => navigate(id)}
              className={page === id ? "active" : ""}
            >
              <Icon size={19} />
              <span>
                {title}
                <small>{en}</small>
              </span>
              <em>{String(i + 1).padStart(2, "0")}</em>
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="board-chip">
            <Command size={25} />
            <div>
              <strong>Tang Mega 60K</strong>
              <small>
                GW5AT-60B · {s?.protocol === "hub" ? "综合固件" : "硬件实验室"}
              </small>
            </div>
            <i className={live ? "online" : ""} />
          </div>
          <span className="version">
            RUST + TAURI <b>v2.0</b>
          </span>
        </div>
      </aside>
      <div className="main-shell">
        <header className="topbar">
          <div className="breadcrumb">
            工作空间 <ChevronRight size={14} />
            <strong>{item.title}</strong>
          </div>
          <div className="connection-controls">
            <span className={`connection-dot ${live ? "online" : ""}`} />
            <select
              aria-label="串口"
              value={port}
              onChange={(e) => setPort(e.target.value)}
              disabled={live || working || s?.connection === "connecting"}
            >
              <option value="">选择串口</option>
              {ports.map((p) => (
                <option key={p.name} value={p.name}>
                  {p.name} · {p.description}
                </option>
              ))}
            </select>
            <button className="icon-button" title="刷新串口" onClick={refresh}>
              <RefreshCw size={16} />
            </button>
            <button
              className={live ? "connected" : "primary"}
              disabled={working || !port}
              onClick={connect}
            >
              {working || s?.connection === "connecting" ? (
                <LoaderCircle size={16} className="spin" />
              ) : live ? (
                <Plug size={16} />
              ) : (
                <Power size={16} />
              )}{" "}
              {s?.connection === "connecting"
                ? "断开"
                : live
                  ? "已连接 · 断开"
                  : "连接设备"}
            </button>
          </div>
        </header>
        <main
          className="main-scroll"
          ref={scrollRef}
          onScroll={updateScroll}
          tabIndex={0}
          aria-label="页面内容，可上下滚动"
        >
          <div className="page-content" ref={contentRef}>
            <div className="page-heading">
              <div>
                <span className="eyebrow">{item.en} / TANG HARDWARE LAB</span>
                <h1>{item.title}</h1>
                <p>
                  {
                    (
                      {
                        overview: "一次连接，掌握每个输入与每次反馈。",
                        keyboard: "实时读取、端点校准与 FPGA 灯效控制。",
                        encoders: "五路独立计数，观察旋转方向与信号质量。",
                        joystick: "直观呈现方向、按压和数字输入状态。",
                        touchpad: "还原实物比例，观察双板触点与电极响应。",
                        guitar: "FPGA 负责判弦，电脑原生音频负责发声。",
                        games: "把硬件变成游戏，规则与计分运行在 FPGA。",
                      } as Record<Page, string>
                    )[page]
                  }
                </p>
              </div>
              <button
                className={`session-button ${sessionOpen ? "selected" : ""}`}
                onClick={() => setSessionOpen(!sessionOpen)}
              >
                <Settings2 size={17} />
                会话工具
                <ChevronRight size={15} />
              </button>
            </div>
            {sessionOpen && (
              <section className="session-tools">
                <button
                  disabled={!live}
                  onClick={() => act({ kind: "record" })}
                >
                  {s?.recording ? <Square size={15} /> : <Circle size={15} />}{" "}
                  {s?.recording ? "停止录制" : "录制原始数据"}
                </button>
                <button onClick={() => file("replay")}>
                  <Play size={15} />
                  历史回放
                </button>
                <button onClick={() => file("diagnostics")}>
                  <Download size={15} />
                  导出诊断
                </button>
                {replay && (
                  <button onClick={() => act({ kind: "disconnect" })}>
                    <X size={15} />
                    退出回放
                  </button>
                )}
                <span>
                  {s?.recording ? "● 正在保存全部串口帧" : "原始记录保存在本机"}
                </span>
              </section>
            )}
            {replay && (
              <div className="replay-banner">
                <Play size={18} />
                <span>
                  历史回放 · {Math.round((s?.replay_progress ?? 0) * 100)}%
                  <small>
                    禁止发送硬件命令，音频已静音。按字节定速播放，不还原精确动作时间。
                  </small>
                </span>
              </div>
            )}
            {(s?.connection === "error" || s?.protocol === "unsupported") && (
              <div className="error-banner">
                <WifiOff size={18} />
                {s.message}
              </div>
            )}
            {!s ? (
              <div className="loading">
                <LoaderCircle className="spin" size={24} />
                <h3>正在启动硬件实验室</h3>
                <p>连接 Rust 原生后端…</p>
              </div>
            ) : (
              <>
                {page === "overview" && <Overview s={s} navigate={navigate} />}
                {page === "keyboard" && (
                  <KeyboardPage
                    s={s}
                    act={act}
                    selected={selected}
                    setSelected={setSelected}
                    file={file}
                  />
                )}
                {page === "encoders" && <EncodersPage s={s} act={act} />}
                {page === "joystick" && <JoystickPage s={s} act={act} />}
                {page === "touchpad" && <TouchpadPage s={s} act={act} />}
                {page === "guitar" && <GuitarPage s={s} act={act} />}
                {page === "games" && <GamesPage s={s} act={act} />}
              </>
            )}
            <footer className="page-footer">
              <span>TANG HARDWARE LAB</span>
              <span>在真实硬件上，探索每一种可能。</span>
              <span>LOCAL / NATIVE</span>
            </footer>
          </div>
        </main>
        {scroll.needed && (
          <div className="scroll-controls" aria-label="页面滚动">
            <button
              title="向上滚动"
              aria-label="向上滚动"
              disabled={scroll.top}
              onClick={() => scrollPage(-1)}
            >
              <ChevronUp size={18} />
            </button>
            <button
              title="向下滚动"
              aria-label="向下滚动"
              disabled={scroll.bottom}
              onClick={() => scrollPage(1)}
            >
              <ChevronDown size={18} />
            </button>
          </div>
        )}
        <div className="statusbar">
          <span>
            <i className={live ? "online" : ""} />
            {live
              ? `${s?.port} · 115200`
              : replay
                ? "历史回放"
                : s?.connection === "connecting"
                  ? "正在连接"
                  : "未连接"}
          </span>
          <span>
            {s?.transfer.busy ? (
              <LoaderCircle size={12} className="spin" />
            ) : s?.board?.configured ? (
              <Check size={12} />
            ) : null}
            {s?.transfer.message || s?.message || "准备就绪"}
          </span>
          <span>
            RX {bytes(s?.rx_bytes ?? 0)} <em /> TX {bytes(s?.tx_bytes ?? 0)}{" "}
            <em /> {s?.fresh_count ?? 0}/40
          </span>
        </div>
      </div>
      {notice && (
        <div role="status" className={`toast ${noticeError ? "error" : ""}`}>
          {noticeError ? <WifiOff size={18} /> : <CheckCircle2 size={18} />}
          <span>{notice}</span>
          <button aria-label="关闭提示" onClick={() => setNotice("")}>
            <X size={16} />
          </button>
        </div>
      )}
    </div>
  );
}
