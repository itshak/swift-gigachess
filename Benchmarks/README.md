# Benchmarks

Throughput comparison for `swift-gigachess` vs native Rust `gigachess 0.1.2`,
measured on one machine over identical deterministic corpora.

## Parity harness (authoritative)

Two harnesses measure the same workloads on the same corpus:

- **Rust:** `cargo bench --bench ffi_parity --manifest-path rust/Cargo.toml`
  (criterion 0.5) — every timed call goes through the real `extern "C"`
  entries, i.e. the exact path Swift calls into, plus native references
  (`perft_d5_native`, `codec_replay_native`).
- **Swift:** `swift run -c release GigaBenchmarks` — median wall times over
  repeated rounds, printed as `RESULT <name>=<milliseconds>` lines.

Both generate the same corpus independently (xorshift seed
`0xBE11_0000_C0DE_0001`, 40 games × ≤100 plies, checked plays, `"*"`
render — mirroring gigachess `codec_bench.rs`) plus a 48-ply line
(seed `0x1234_5678_9ABC_DEF0`). Each side prints corpus fingerprints
(plies, word-xor, line-xor); `scripts/compare-bench.py` refuses to compare
unless they match exactly.

`bench.yml` runs both on macOS, joins them into one table (Swift/native
ratios), and uploads the raw logs. Ratios are indicative — shared CI
runners are noisy — and never gate: the compare step fails only on corpus
mismatch or missing rows.

## Official numbers

`Benchmarks/results.log` holds numbers transcribed from green `bench` runs
(committed). The table below tracks the latest transcription.

## First numbers (pinned engine 0.1.2)

| Workload | Native Rust | Swift wrapper | Notes |
|---|---|---|---|
| perft(3) startpos (8,902 nodes) | ~16 µs (540M nodes/s) | ~16–25 µs | 1 FFI call, movegen dominates |
| perft(4) startpos (197,281 nodes) | ~365 µs | ~365–550 µs | same |
| parse Opera game (33 ply) | ~20 µs | ~25–40 µs | 1 FFI call per game |
| moves2 → SAN export (33 ply) | ~30 µs | ~35–55 µs | SAN disambiguation dominates |
| replay 33-ply → 34 hashes | ~5 µs | ~6–10 µs | incremental, no SAN |

Raw FFI call overhead is ~1ns (direct `extern "C"` call, no serialization);
bulk workloads are movegen/SAN-bound, so Swift lands within noise plus the
copy of the 144-byte board per call (memcpy, ~2ns).

## Reproducing

```bash
cargo bench --bench ffi_parity --manifest-path rust/Cargo.toml
swift run -c release GigaBenchmarks
python3 scripts/compare-bench.py /tmp/rust-bench.log /tmp/swift-bench.log
```

`swift test --filter PerformanceTests` remains the lightweight CI smoke
(order-of-magnitude, not nanosecond parity). Transcribe new official
numbers to `Benchmarks/results.log` (committed) after green `bench` runs.
