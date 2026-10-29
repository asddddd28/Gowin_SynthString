"""Build the clearly labeled historical seed from this board's captured evidence."""
import re
import statistics
from pathlib import Path

from keyboard_core import KeyCalibration, Profile


def read_keys(path):
    values = {k: [] for k in range(1, 33)}
    for key, value in re.findall(rb"K(\d{2}):([0-9A-F]{3})\r\n", path.read_bytes()):
        values[int(key)].append(int(value, 16))
    return values


def main():
    root = Path(__file__).resolve().parent.parent
    rest_file = root / "reports/keyboard_final_idle_after_rework_20261029_025354.bin"
    press_file = root / "reports/keyboard_after_cn1_rework_all_keys_20261029_024626.bin"
    rest, press = read_keys(rest_file), read_keys(press_file)
    keys = []
    for key in range(1, 33):
        baseline = sorted(rest[key])
        held = [value for value in press[key] if value < 400]
        if len(baseline) < 60 or len(held) < 8:
            raise ValueError(f"Insufficient evidence for K{key:02d}")
        spread = baseline[int((len(baseline) - 1) * .95)] - baseline[int((len(baseline) - 1) * .05)]
        keys.append(KeyCalibration(statistics.median(baseline), statistics.median(held), spread))
    profile = Profile(keys, "历史实测 · 2026-10-29", "Tang Mega 60K / Dock31004 / DEBUG2025030317B. "
                      "Rest: keyboard_final_idle_after_rework_20261029_025354.bin; "
                      "bottom: keyboard_after_cn1_rework_all_keys_20261029_024626.bin. "
                      "Recalibrate after mechanical/magnet changes; relative endpoint scale, not millimeters.")
    path = Path(__file__).with_name("measured_profile.json")
    profile.save(path)
    print(f"Saved historical seed: {path}; 32 real measured keys")


if __name__ == "__main__":
    main()
