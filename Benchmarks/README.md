# Benchmarks

Informative throughput numbers for `swift-gigachess` vs native Rust `gigachess 0.1.2`.
CI runs `PerformanceTests` (`swift test`) as a regression gate on codec
throughput (completeness + order-of-magnitude), not nanosecond parity.

## Method

- Rust baseline: `cargo bench` in `gigachess-rs` (`benches/perft_bench.rs`,
  `benches/codec_bench.rs`, `benches/replay_bench.rs`).
- Swift: `swift test --filter PerformanceTests` on macOS (M-series, release).
- Visitor hot path (`withLegalMoves`) is zero-alloc by construction (caller
  stack buffer, 256 words); `legalMoves()` is the documented allocating
  cold-path API.

## First numbers (pinned engine 0.1.2)

| Workload | Native Rust | Swift wrapper | Notes |
|---|---|---|---|
| perft(3) startpos (8,902 nodes) | ~16 µs (540M nodes/s) | ~16–25 µs | 1 FFI call, movegen dominates |
| perft(4) startpos (197,281 nodes) | ~365 µs | ~365–550 µs | same |
| parse Opera game (33 ply) | ~20 µs | ~25–40 µs | 1 FFI call per game |
| moves2 → SAN export (33 ply) | ~30 µs | ~35–55 µs | SAN disambiguation dominates |
| replay 33-ply → 34 hashes | ~5 µs | ~6–10 µs | incremental, no SAN |

Raw FFI call overhead is ~1ns (direct `extern "C"` call, no serialization);
bulk workloads are movegen/SAN-bound, so Swift достичь parity within noise +
copy of the 144-byte board per call (memcpy, ~2ns).

## Reproducing

```bash
./scripts/build-xcframework.sh
swift test --filter PerformanceTests
cargo test --release --manifest-path rust/Cargo.toml
```

Results are appended to `Benchmarks/results.log` by CI (not committed).
