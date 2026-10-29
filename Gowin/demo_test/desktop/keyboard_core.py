"""Streaming protocol, per-key calibration, and live state independent of the GUI."""
from __future__ import annotations

import json
import math
import os
import re
import statistics
import tempfile
from collections import deque
from dataclasses import asdict, dataclass
from pathlib import Path
from board_protocol import decode_status, decode_game_status

KEYS = 32
STALE_SECONDS = 0.6
MIN_SPAN = 100


class StreamParser:
    def __init__(self):
        self.buffer = bytearray()
        self.records = self.discarded = self.sequence_errors = self.scans = 0
        self.previous = None
        self.progress = 0
        self.statuses = deque(maxlen=256)
        self.status_errors = 0
        self.game_statuses = deque(maxlen=256)
        self.game_errors = 0

    def feed(self, data: bytes):
        self.buffer.extend(data)
        result = []
        while self.buffer:
            markers = [p for p in (self.buffer.find(b"K"), self.buffer.find(b"@"), self.buffer.find(b"#")) if p >= 0]
            marker = min(markers) if markers else -1
            if marker < 0:
                self.discarded += len(self.buffer)
                self.buffer.clear()
                break
            if marker:
                self.discarded += marker
                del self.buffer[:marker]
            if self.buffer[:1] == b'#':
                if len(self.buffer) < 37:
                    break
                try:
                    self.game_statuses.append(decode_game_status(bytes(self.buffer[:37])))
                    del self.buffer[:37]
                except ValueError:
                    self.game_errors += 1
                    self.discarded += 1
                    del self.buffer[0]
                continue
            if self.buffer[:1] == b'@':
                if len(self.buffer) < 23:
                    break
                try:
                    self.statuses.append(decode_status(bytes(self.buffer[:23])))
                    del self.buffer[:23]
                except ValueError:
                    self.status_errors += 1
                    self.discarded += 1
                    del self.buffer[0]
                continue
            if len(self.buffer) < 9:
                break
            candidate = bytes(self.buffer[:9])
            match = re.fullmatch(rb"K(0[1-9]|[12][0-9]|3[0-2]):([0-9A-F]{3})\r\n", candidate)
            if not match:
                del self.buffer[0]
                self.discarded += 1
                continue
            del self.buffer[:9]
            key, value = int(match[1]), int(match[2], 16)
            if self.previous is not None and key != self.previous % KEYS + 1:
                self.sequence_errors += 1
            self.previous = key
            self.progress = 1 if key == 1 else self.progress + 1 if key == self.progress + 1 else 0
            if self.progress == KEYS:
                self.scans += 1
                self.progress = 0
            self.records += 1
            result.append((key, value))
        return result


def number(value, name, low=0, high=4095):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} 必须是数值")
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"{name} 超出范围 {low}～{high}")
    return float(value)


@dataclass(frozen=True)
class KeyCalibration:
    rest: float
    bottom: float
    noise: float = 0

    def __post_init__(self):
        number(self.rest, "松开值")
        number(self.bottom, "到底值")
        number(self.noise, "噪声")
        if abs(self.bottom - self.rest) < MIN_SPAN:
            raise ValueError(f"有效行程不足 {MIN_SPAN} 个ADC计数")

    def depth(self, value):
        return max(0.0, min(1.0, (value - self.rest) / (self.bottom - self.rest)))


@dataclass
class Profile:
    keys: list
    name: str = "未校准"
    source: str = ""
    press_threshold: float = 0.50
    release_threshold: float = 0.35

    @classmethod
    def empty(cls):
        return cls([None] * KEYS)

    def validate(self):
        if len(self.keys) != KEYS or any(k is not None and not isinstance(k, KeyCalibration) for k in self.keys):
            raise ValueError("配置必须包含32个有效键槽")
        p = number(self.press_threshold, "触发阈值", 0.01, 1)
        r = number(self.release_threshold, "释放阈值", 0, 0.99)
        if r >= p:
            raise ValueError("释放阈值必须小于触发阈值")
        if not isinstance(self.name, str) or len(self.name) > 200 or not isinstance(self.source, str) or len(self.source) > 2000:
            raise ValueError("配置名称或来源无效")

    def to_dict(self):
        self.validate()
        return dict(format="TangKeyboardCalibration", version=1, name=self.name, source=self.source,
                    press_threshold=self.press_threshold, release_threshold=self.release_threshold,
                    keys=[dict(key=i + 1, calibration=asdict(k) if k else None) for i, k in enumerate(self.keys)])

    @classmethod
    def from_dict(cls, data):
        if not isinstance(data, dict) or data.get("format") != "TangKeyboardCalibration" or data.get("version") != 1:
            raise ValueError("不是受支持的键盘校准配置（v1）")
        entries = data.get("keys")
        if not isinstance(entries, list) or len(entries) != KEYS:
            raise ValueError("配置必须有32个键")
        keys = []
        for i, entry in enumerate(entries):
            if not isinstance(entry, dict) or type(entry.get("key")) is not int or entry["key"] != i + 1:
                raise ValueError("键号缺失、重复或顺序不正确")
            cal = entry.get("calibration")
            if cal is None:
                keys.append(None)
            elif isinstance(cal, dict) and set(cal) == {"rest", "bottom", "noise"}:
                keys.append(KeyCalibration(**cal))
            else:
                raise ValueError(f"K{i + 1:02d} 校准字段无效")
        profile = cls(keys, data.get("name", "校准配置"), data.get("source", ""),
                      data.get("press_threshold", .5), data.get("release_threshold", .35))
        profile.validate()
        return profile

    @classmethod
    def load(cls, path):
        path = Path(path)
        if path.stat().st_size > 1024 * 1024:
            raise ValueError("配置文件过大")
        return cls.from_dict(json.loads(path.read_text(encoding="utf-8-sig")))

    def save(self, path):
        payload = json.dumps(self.to_dict(), ensure_ascii=False, indent=2)
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp, path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)


class CalibrationSession:
    """Candidate data stays separate until every requested key is ready and applied."""
    def __init__(self, targets, now):
        self.targets = tuple(targets)
        if not self.targets or any(k not in range(1, KEYS + 1) for k in self.targets):
            raise ValueError("无效校准范围")
        self.stage = "rest"
        self.started = now
        self.last = {k: now for k in self.targets}
        self.samples = {k: [] for k in self.targets}
        self.rest = {}
        self.noise = {}
        self.bottom = {}
        self.recent = {k: deque(maxlen=7) for k in self.targets}
        self.error = ""

    def feed(self, key, value, now):
        if key not in self.samples or self.stage not in ("rest", "press"):
            return
        if now - self.last[key] > STALE_SECONDS:
            self.abort("数据中断，候选校准已取消；原配置保留")
            return
        self.last[key] = now
        if self.stage == "rest":
            self.samples[key].append(value)
        elif self.stage == "press":
            window = self.recent[key]
            window.append(value)
            if len(window) == 7:
                # Seven-sample median rejects single-frame corruption and brief spikes.
                endpoint = statistics.median(window)
                span = abs(endpoint - self.rest[key])
                required = max(MIN_SPAN, self.noise[key] * 8)
                if span >= required and span > abs(self.bottom.get(key, self.rest[key]) - self.rest[key]):
                    self.bottom[key] = endpoint

    def tick(self, now):
        if self.stage not in ("rest", "press"):
            return
        if any(now - self.last[k] > STALE_SECONDS for k in self.targets):
            self.abort("校准时数据超时；原配置保留")
            return
        if self.stage == "rest" and now - self.started >= 2:
            for key in self.targets:
                values = sorted(self.samples[key])
                if len(values) < 30:
                    self.abort(f"K{key:02d} 样本不足，请检查数据刷新后重试")
                    return
                spread = values[int((len(values) - 1) * .95)] - values[int((len(values) - 1) * .05)]
                if spread > 60:
                    self.abort(f"K{key:02d} 零点不稳定，请全部松开后重试")
                    return
                self.rest[key] = statistics.median(values)
                self.noise[key] = float(spread)
            self.stage = "ready"

    def start_press(self, now):
        if self.stage != "ready":
            raise ValueError("请先完成松开位置采集")
        self.stage = "press"
        self.last = {k: now for k in self.targets}

    def abort(self, reason):
        self.stage = "error"
        self.error = reason

    @property
    def complete(self):
        return self.stage == "press" and len(self.bottom) == len(self.targets)

    def apply(self, previous, name, source):
        if not self.complete:
            raise ValueError("仍有按键没有采到有效终点")
        keys = list(previous.keys)
        for key in self.targets:
            keys[key - 1] = KeyCalibration(self.rest[key], self.bottom[key], self.noise[key])
        candidate = Profile(keys, name, source, previous.press_threshold, previous.release_threshold)
        candidate.validate()
        return candidate


class KeyboardState:
    def __init__(self, profile=None):
        self.profile = profile or Profile.empty()
        self.session = None
        self.reset_stream()

    def reset_stream(self):
        self.raw = [None] * KEYS
        self.filtered = [None] * KEYS
        self.updated = [-math.inf] * KEYS
        self.pressed = [False] * KEYS
        self.histories = [deque(maxlen=480) for _ in range(KEYS)]
        self.hardware_mode = False
        self.board_updated = -math.inf
        self.events = deque(maxlen=100)
        if self.session:
            self.session.abort("连接已改变，候选校准取消；原配置保留")

    def set_profile(self, profile):
        profile.validate()
        self.profile = profile
        if not self.hardware_mode:
            self.pressed = [False] * KEYS
        self.filtered = list(self.raw)

    def update(self, key, value, now):
        index = key - 1
        stale = now - self.updated[index] > STALE_SECONDS
        self.raw[index] = value
        old = self.filtered[index]
        self.filtered[index] = float(value) if old is None or stale else old + .4 * (value - old)
        self.updated[index] = now
        self.histories[index].append((now, value))
        if self.session:
            self.session.feed(key, value, now)
        cal = self.profile.keys[index]
        if stale:
            self.pressed[index] = False
        depth = cal.depth(self.filtered[index]) if cal else None
        was = self.pressed[index]
        if self.hardware_mode:
            return depth
        if depth is not None:
            if depth >= self.profile.press_threshold:
                self.pressed[index] = True
            elif depth <= self.profile.release_threshold:
                self.pressed[index] = False
        else:
            self.pressed[index] = False
        if was != self.pressed[index]:
            self.events.append((now, key, self.pressed[index]))
        return depth

    def tick(self, now):
        for i in range(KEYS):
            if now - self.updated[i] > STALE_SECONDS:
                self.pressed[i] = False
        if self.hardware_mode and now - self.board_updated > STALE_SECONDS:
            self.pressed = [False] * KEYS
        if self.session:
            self.session.tick(now)

    def apply_board_state(self, status, now):
        self.hardware_mode = True
        self.board_updated = now
        mask = status.pressed if status.configured else 0
        for i in range(KEYS):
            value = bool(mask & (1 << i))
            if self.pressed[i] != value:
                self.events.append((now, i + 1, value))
            self.pressed[i] = value

    def fresh(self, index, now):
        return now - self.updated[index] <= STALE_SECONDS

    def depth(self, index, now):
        cal = self.profile.keys[index]
        return cal.depth(self.filtered[index]) if cal and self.filtered[index] is not None and self.fresh(index, now) else None
