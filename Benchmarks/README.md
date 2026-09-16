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
(committed). The table below tracks the latest transcription (2026-09-15,
macOS arm64 CI, run 35038585769, commit 073db63):

| workload | native Rust | Swift wrapper | Swift/native |
|---|---|---|---|
| perft d5 (4.87M nodes) | 12.32 ms (395 Mnps) | 10.92 ms (445 Mnps) | 0.89x |
| movegen fill | 112.3 ns | 142.7 ns | 1.27x |
| 48-ply make/unmake | 26.6 ns | 22.1 ns | 0.83x |
| SAN render x48 | 58.2 ns | 107.6 ns | 1.85x |
| zobrist read | 8.7 ns | 2.6 ns (optimizer artifact, see log) | 0.30x |
| parse 40 games | 11.6 us | 10.0 us | 0.86x |
| export 40 games | 14.1 us | 15.9 us | 1.13x |
| replay 40 games | 3.6 us | 3.4 us | 0.94x |

See `results.log` for caveats (shared-runner noise, sample sizes, the
zobrist optimizer artifact, and where the real SAN `String` cost sits).

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
