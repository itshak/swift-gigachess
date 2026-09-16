#!/usr/bin/env python3
"""Merge Rust criterion and Swift GigaBenchmarks output into one table.

Usage: compare-bench.py <rust-bench.log> <swift-bench.log> [--out table.md]

Parses criterion `time: [lo med hi]` lines (median) and Swift
`RESULT <name>=<milliseconds>` lines, asserts both harnesses ran the
identical deterministic corpus (plies + xor fingerprints), and prints a
Markdown comparison with Swift/native ratios.

Exit nonzero only on corpus mismatch or missing rows — ratios are
informative (shared runners are noisy), never a gate.

Unit convention: criterion medians convert to ms; per-op units derive
from Swift `ops_*` lines ( Rust iters are one op-group each, see ROWS).
"""
import re
import sys

PERFT_D5_NODES = 4_865_609

# key -> (label, swift_ms_key, rust_bench, swift_unit, rust_per, fmt)
# swift_unit: how to render the Swift median; rust_per: divisor for the
# native per-iter median to reach the same unit.
ROWS = [
    ("perft_d5", "perft d5 (4.87M nodes)", "ms+Mnps", 1.0),
    ("movegen_fill", "movegen fill", "ns/op", 500.0 / 1.0),  # swift ms/round over 500 fills
    ("play_unmake_48", "48-ply make/unmake", "ns/op", 96.0 / 1.0),
    ("san_48", "SAN render x48", "ns/op", 48.0 / 1.0),
    ("zobrist", "zobrist read", "ns/op", 100000.0 / 1.0),
    ("codec_parse", "parse 40 games", "us/game", 40.0 / 1.0),
    ("codec_export", "export 40 games", "us/game", 40.0 / 1.0),
    ("codec_replay", "replay 40 games", "us/game", 40.0 / 1.0),
]
# Rust per-iter divisors to reach the row unit (criterion median -> unit):
# perft_d5: ms direct; movegen_fill: 1 fill -> ns; play_unmake_48: 48-cycle -> /96;
# san_48: 48 renders -> /48; zobrist: 1 read -> ns; codec_*: 40 games -> us/game.
RUST_DIVISOR = {
    "perft_d5": ("ms", 1.0),
    "movegen_fill": ("ns", 1.0),
    "play_unmake_48": ("ns", 96.0),
    "san_48": ("ns", 48.0),
    "zobrist": ("ns", 1.0),
    "codec_parse": ("us", 40.0),
    "codec_export": ("us", 40.0),
    "codec_replay": ("us", 40.0),
}

# Note: criterion prints microseconds with the micro sign (U+00B5), and some
# locales/tools emit Greek mu (U+03BC) or ASCII "us" — accept all three.
UNIT_TO_MS = {"ns": 1e-6, "us": 1e-3, "µs": 1e-3, "μs": 1e-3,
                "ms": 1.0, "s": 1e3}


def parse_rust(path):
    times = {}
    corpus = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(
        r"^(ffi/(\S+))\s+time:\s*\[([\d.]+)\s*(\S+)\s+([\d.]+)\s*(\S+)\s+([\d.]+)\s*(\S+)\]",
        text,
        re.M,
    ):
        key, med, unit = m.group(2), float(m.group(5)), m.group(6)
        times[key] = med * UNIT_TO_MS[unit]
    m = re.search(r"^CORPUS games=(\d+) plies=(\d+) xor=(\d+)\s*$", text, re.M)
    if m:
        corpus.update(plies=int(m.group(2)), xor=int(m.group(3)))
    m = re.search(r"^CORPUS line48_xor=(\d+)\s*$", text, re.M)
    if m:
        corpus["line48_xor"] = int(m.group(1))
    return times, corpus


def parse_swift(path):
    vals = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"^RESULT (\w+)=([0-9.eE+-]+)\s*$", text, re.M):
        vals[m.group(1)] = float(m.group(2))
    return vals


def fmt_ms(ms):
    if ms < 0.001:
        return f"{ms * 1e6:.1f} ns"
    if ms < 1.0:
        return f"{ms * 1e3:.1f} us"
    if ms < 1000.0:
        return f"{ms:.2f} ms"
    return f"{ms / 1000.0:.2f} s"


def main():
    rust_log, swift_log = sys.argv[1], sys.argv[2]
    out_path = None
    if "--out" in sys.argv:
        out_path = sys.argv[sys.argv.index("--out") + 1]
    rust_times, rust_corpus = parse_rust(rust_log)
    swift = parse_swift(swift_log)

    # Corpus identity gate: identical deterministic input or no comparison.
    problems = []
    for k in ("plies", "xor", "line48_xor"):
        rk, sk = rust_corpus.get(k), swift.get(f"corpus_{k}")
        if rk is None or sk is None:
            problems.append(f"missing corpus fingerprint {k}")
        elif int(rk) != int(sk):
            problems.append(f"corpus mismatch {k}: rust={rk} swift={sk}")
    missing = [key for key, _, _, _ in ROWS
               if key not in rust_times or key not in swift]
    if missing:
        problems.append(f"missing rows: {sorted(set(missing))}")
    if problems:
        print("BENCH COMPARISON REFUSED:")
        for p in problems:
            print(f"  - {p}")
        return 1

    lines = [
        "| workload | native Rust | Swift wrapper | Swift/native |",
        "|---|---|---|---|",
    ]
    for key, label, unit, swift_ops in ROWS:
        native_ms = rust_times[key]
        swift_ms = swift[key]
        r_unit, r_div = RUST_DIVISOR[key]
        if unit == "ms+Mnps":
            n_str = f"{fmt_ms(native_ms)} ({PERFT_D5_NODES / native_ms / 1e3:.0f} Mnps)"
            s_str = f"{fmt_ms(swift_ms)} ({PERFT_D5_NODES / swift_ms / 1e3:.0f} Mnps)"
            ratio = swift_ms / native_ms
        elif unit == "ns/op":
            n_val = native_ms * 1e6 / r_div
            s_val = swift_ms * 1e6 / swift_ops
            n_str, s_str = f"{n_val:.1f} ns", f"{s_val:.1f} ns"
            ratio = s_val / n_val if n_val > 0 else float("nan")
        else:  # us/game
            n_val = native_ms * 1e3 / r_div
            s_val = swift_ms * 1e3 / swift_ops
            n_str, s_str = f"{n_val:.1f} us", f"{s_val:.1f} us"
            ratio = s_val / n_val if n_val > 0 else float("nan")
        flag = " ⚠" if ratio > 2.0 else ""
        lines.append(f"| {label} | {n_str} | {s_str} | {ratio:.2f}x{flag} |")
    lines += [
        "",
        "Ratios are indicative (shared CI runners are noisy); both columns are",
        "medians measured on the same machine in one job over identical",
        f"deterministic corpora (40 games, {int(swift['corpus_plies'])} plies).",
    ]
    table = "\n".join(lines) + "\n"
    print(table)
    if out_path:
        open(out_path, "w").write(table)
    return 0


if __name__ == "__main__":
    sys.exit(main())
