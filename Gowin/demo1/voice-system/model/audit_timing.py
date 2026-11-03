"""Group Gowin routed timing paths by leaf RTL owner, without altering a build.

Usage: python audit_timing.py REPORT_HTML OUTPUT_DIRECTORY
Only Python's standard library is required. The streaming parser also handles
large expanded reports; it keeps one detailed path table in memory at a time.
"""
import csv
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from html.parser import HTMLParser
from pathlib import Path


EP = "Endpoint_Inst/Endpoint_Inst_0"
RT = EP + "/Runtime_Inst"
VE = RT + "/Voice_Inst"
FX = RT + "/Fx_Inst"
OWNERS = {
    "": "SynthSystemTop", "Scanner_Inst": "KeyboardSampler",
    "Thresholds_Inst": "LatencyKeyThresholds", "Boot_Inst": "SynthBootSequencer",
    "Keys_Inst": "SynthKeyboardSource", "Host_Inst": "SynthUartControl",
    "Host_Inst/Receiver_Inst": "UartRx", "Host_Inst/Transmitter_Inst": "EncoderUartTx",
    "Arbiter_Inst": "SynthCommandArbiter", "Master_Inst": "SynthAxiMaster",
    "Endpoint_Inst": "AxiSynthEndpoint", EP: "AxiVoiceEndpoint",
    RT: "AxisSynthSystem", VE: "VoiceSynthEngine",
    VE + "/Modulation_Inst": "VoiceModulation",
    VE + "/Modulation_Inst/Lfo_Inst": "AxisLfoStep",
    VE + "/Operator_Inst": "AxisFmOperator",
    VE + "/Operator_Inst/Envelope_Inst": "AxisEnvelopeMulti",
    VE + "/Operator_Inst/Envelope_Inst/Segment_Inst": "AxisEnvelopeSegment",
    VE + "/Operator_Inst/DxEnvelope_Inst": "AxisDxEnvelope",
    FX: "AxisFxEngine", FX + "/Delay_Inst": "AxisStereoDelay",
    FX + "/Reverb_Inst": "AxisSchroederReverb", "Audio_Inst": "SynthPcmOutput",
    RT + "/FxDomain/Fx_Inst": "AxisFxEngine",
    RT + "/FxDomain/Fx_Inst/Delay_Inst": "AxisStereoDelay",
    RT + "/FxDomain/Fx_Inst/Reverb_Inst": "AxisSchroederReverb",
}


def owner(node):
    return next(OWNERS[p] for p in sorted(OWNERS, key=len, reverse=True)
                if not p or node.startswith(p + "/"))


def stem(node):
    cell = node.rsplit("/", 2)[-2] if "/" in node else node
    cell = re.sub(r"\[\d+\]", "[]", cell)
    return re.sub(r"_\d+_s\d+$", "_BIT", cell)


class TimingParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.section = ""
        self.rows = None
        self.row = None
        self.cell = None
        self.paths = defaultdict(list)
        self.tables = {}
        self.detail_index = Counter()
        self.pending = None

    def close_cell(self):
        if self.cell is not None:
            if self.row is not None:
                self.row.append("".join(self.cell).strip())
            self.cell = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and attrs.get("name"):
            self.section = attrs["name"]
        if tag == "table":
            self.rows = []
        elif tag == "tr":
            self.close_cell()
            self.row = []
        elif tag in ("td", "th"):
            self.close_cell()
            self.cell = []

    def handle_data(self, text):
        if self.cell is not None:
            self.cell.append(text)

    def handle_endtag(self, tag):
        if tag in ("td", "th"):
            self.close_cell()
        elif tag == "tr" and self.rows is not None:
            self.close_cell()
            self.rows.append(self.row)
            self.row = None
        elif tag == "table" and self.rows is not None:
            self.finish_table(self.section, self.rows)
            self.rows = None

    def finish_table(self, section, rows):
        if not rows:
            return
        if section.endswith("_Slack_Table"):
            kind = section.split("_")[0].lower()
            for r in rows[1:]:
                if len(r) != 9:
                    continue
                self.paths[kind].append({
                    "index": int(r[0]), "slack_ns": float(r[1]),
                    "slack_text": r[1],
                    "reported_negative": r[1].startswith("-"),
                    "from": r[2], "to": r[3], "from_clock": r[4], "to_clock": r[5],
                    "relation_ns": float(r[6]), "skew_ns": float(r[7]),
                    "data_delay_ns": float(r[8]),
                    "from_module": owner(r[2]), "to_module": owner(r[3]),
                    "from_family": stem(r[2]), "to_family": stem(r[3]),
                })
            return
        if section in ("Setup_Analysis", "Hold_Analysis", "Recovery_Analysis", "Removal_Analysis"):
            kind = section.split("_")[0].lower()
            if rows[0][0] == "Slack":
                i = self.detail_index[kind]
                self.detail_index[kind] += 1
                self.pending = self.paths[kind][i]
            elif rows[0][0] == "AT" and self.pending is not None:
                path = self.pending
                self.pending = None  # Next table is capture clock, not data.
                arcs = [dict(zip(rows[0], r)) for r in rows[1:] if len(r) == len(rows[0])]
                start = next((i for i, a in enumerate(arcs) if a["NODE"] == path["from"]), None)
                if start is None:
                    path["arc_status"] = "start_pin_not_found"
                    return
                arcs = arcs[start:]
                totals = defaultdict(float)
                for a in arcs:
                    totals[a["TYPE"]] += float(a["DELAY"])
                path["delay_by_type_ns"] = {k: round(v, 3) for k, v in totals.items()}
                path["arc_sum_error_ns"] = round(sum(totals.values()) - path["data_delay_ns"], 3)
                path["net_delay_ns"] = round(totals.get("tNET", 0), 3)
                path["cell_delay_ns"] = round(sum(v for k, v in totals.items() if k != "tNET"), 3)
                path["net_fraction"] = round(path["net_delay_ns"] / path["data_delay_ns"], 4) if path["data_delay_ns"] else 0
                path["arc_status"] = "ok" if abs(path["arc_sum_error_ns"]) <= 0.04 else "sum_mismatch"
                path["longest_arcs"] = sorted(arcs, key=lambda a: float(a["DELAY"]), reverse=True)[:5]
                path["data_modules"] = sorted({owner(a["NODE"]) for a in arcs})
                path["named_signals"] = sorted({stem(a["NODE"]) for a in arcs
                    if stem(a["NODE"]).startswith(("reg_", "wire_", "mem_", "flag_", "dec_", "cnt_"))})
                path["net_arc_count"] = sum(a["TYPE"] == "tNET" for a in arcs)
                path["cell_arc_count"] = sum(a["TYPE"] != "tNET" for a in arcs)
            return
        self.tables[section] = rows


def run(report, output):
    parser = TimingParser()
    with report.open(encoding="utf8") as f:
        while chunk := f.read(1024 * 1024):
            parser.feed(chunk)
    parser.close()
    output.mkdir(parents=True, exist_ok=True)
    setup = parser.paths["setup"]
    # Gowin rounds to three decimals: a displayed -0.000 is still a violation.
    failing = [p for p in setup if p["reported_negative"]]
    reported = dict(parser.tables.get("STA_Tool_Run_Summary", []))
    expected = int(reported.get("Numbers of Setup Violated Endpoints", -1))
    unique = len({p["to"] for p in failing})
    groups = defaultdict(list)
    families = defaultdict(list)
    for p in failing:
        groups[(p["from_module"], p["to_module"])].append(p)
        families[(p["from_module"], p["to_module"], p["from_family"], p["to_family"])].append(p)

    def summarize(items):
        result = []
        for key, paths in items.items():
            worst = min(paths, key=lambda p: p["slack_ns"])
            result.append({"key": list(key), "reported_paths": len(paths),
                           "unique_endpoints": len({p["to"] for p in paths}),
                           "worst_slack_ns": worst["slack_ns"],
                           "reported_slack_sum_ns": round(sum(p["slack_ns"] for p in paths), 3),
                           "worst_path": worst})
        return sorted(result, key=lambda g: g["worst_slack_ns"])

    summary = {
        "source": str(report), "source_sha256": hashlib.sha256(report.read_bytes()).hexdigest(),
        "sta_summary": reported,
        "reported_setup_paths": len(setup), "reported_negative_setup_paths": len(failing),
        "reported_unique_failing_endpoints": unique,
        "expected_failing_endpoints": expected,
        "all_failing_endpoints_covered": unique == expected,
        "parsed_detail_counts": dict(parser.detail_index),
        "arc_status_counts": dict(Counter(p.get("arc_status", "missing") for p in setup)),
        "reported_setup_slack_sum_ns": round(sum(p["slack_ns"] for p in failing), 3),
        "module_pairs": summarize(groups), "families": summarize(families),
        "negative_endpoints_by_owner": dict(Counter(p["to_module"] for p in failing)),
        "tables": {k: v for k, v in parser.tables.items() if k in (
            "Message", "Clock_Report", "Max_Frequency_Report", "Total_Negative_Slack_Report", "High_Fanout_Nets_Report",
            "Route_Congestions_Report", "SDC_Report", "Minimum_Pulse_Width_Report")},
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf8")
    (output / "paths.json").write_text(json.dumps(dict(parser.paths), indent=2, ensure_ascii=False), encoding="utf8")
    fields = ["index", "slack_ns", "slack_text", "reported_negative", "from_module", "to_module", "from", "to", "data_delay_ns",
              "net_delay_ns", "cell_delay_ns", "net_fraction", "skew_ns", "arc_status"]
    for kind, paths in parser.paths.items():
        with (output / (kind + "-paths.csv")).open("w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fields, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(paths)
    with (output / "setup-violations.csv").open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(failing)
    print(json.dumps({k: v for k, v in summary.items() if k not in (
        "tables", "families", "module_pairs")}, ensure_ascii=False, indent=2))
    for g in summary["module_pairs"]:
        print(g["key"], g["reported_paths"], g["worst_slack_ns"])


if __name__ == "__main__":
    run(Path(sys.argv[1]), Path(sys.argv[2]))
