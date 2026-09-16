// ffi_parity.rs — throughput parity benches through OUR FFI layer.
//
// Same workloads and same deterministic corpora as the Swift
// `GigaBenchmarks` harness, so CI can report Swift-vs-native ratios measured
// on one machine. Corpus generation mirrors gigachess 0.1.2
// `benches/codec_bench.rs` exactly (xorshift seed, checked `play`, `"*"`
// result token), so the corpus is also identical to upstream's.
//
// Every timed FFI call goes through the real `extern "C"` entry points
// (catch_unwind + byte copies included) — the exact path Swift calls into.
//
// Run: cargo bench --bench ffi_parity
//
// SPDX-License-Identifier: MIT

use criterion::{
    black_box, criterion_group, criterion_main, BatchSize, Criterion, Throughput,
};
use gigachess::Board;
use gigachess_ffi::{
    GigaBoard, GigaUndo, gigachess_board_legal_moves,
    gigachess_board_make_unchecked, gigachess_board_move_to_san,
    gigachess_board_perft, gigachess_board_play, gigachess_board_startpos,
    gigachess_board_unmake, gigachess_board_zobrist,
    gigachess_moves2_to_san_movetext, gigachess_parse_movetext_to_moves2,
    gigachess_replay_moves2_stream,
};
use std::ffi::CString;
use std::time::Duration;

const CORPUS_GAMES: usize = 40;
const CORPUS_MAX_PLIES: u32 = 100;
const CORPUS_SEED: u64 = 0xBE11_0000_C0DE_0001;
const LINE48_SEED: u64 = 0x1234_5678_9ABC_DEF0;
const START_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

fn xorshift(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

fn ffi_board_startpos() -> GigaBoard {
    let mut gb = GigaBoard { bytes: [0; 144] };
    gigachess_board_startpos(&mut gb);
    gb
}

/// Deterministic corpus identical to gigachess codec_bench: 40 games,
/// xorshift-picked checked plays, SAN movetexts rendered with `"*"`.
/// Returns (movetexts, word lists).
fn generate_corpus() -> (Vec<String>, Vec<Vec<u16>>) {
    let start_fen = Board::startpos().to_fen();
    let mut state = CORPUS_SEED;
    let mut texts = Vec::with_capacity(CORPUS_GAMES);
    let mut games = Vec::with_capacity(CORPUS_GAMES);
    for _ in 0..CORPUS_GAMES {
        let mut board = Board::startpos();
        let mut words = Vec::new();
        for _ in 0..CORPUS_MAX_PLIES {
            let legal = board.legal_moves();
            if legal.is_empty() {
                break;
            }
            let mv = legal[(xorshift(&mut state) % legal.len() as u64) as usize];
            words.push(mv.word());
            board.play(mv).unwrap();
        }
        let bytes: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
        let text =
            gigachess::database::moves2_to_san_movetext(&start_fen, &bytes, "*").unwrap();
        texts.push(text);
        games.push(words);
    }
    (texts, games)
}

/// Deterministic 48-ply startpos line (unchecked advance, fixed seed).
fn generate_line48() -> Vec<u16> {
    let mut board = Board::startpos();
    let mut state = LINE48_SEED;
    let mut out = Vec::with_capacity(48);
    for _ in 0..48 {
        let legal = board.legal_moves();
        if legal.is_empty() {
            break;
        }
        let mv = legal[(xorshift(&mut state) % legal.len() as u64) as usize];
        out.push(mv.word());
        board.play(mv).unwrap();
    }
    assert_eq!(out.len(), 48, "line48 must be a full 48 plies");
    out
}

fn corpus_fingerprint(games: &[Vec<u16>], line: &[u16]) -> (usize, u64, u64) {
    let plies: usize = games.iter().map(|g| g.len()).sum();
    let mut xor = 0u64;
    for g in games {
        for &w in g {
            xor ^= w as u64;
        }
    }
    let mut line_xor = 0u64;
    for &w in line {
        line_xor ^= w as u64;
    }
    (plies, xor, line_xor)
}

fn bench_ffi(c: &mut Criterion) {
    let (texts, games) = generate_corpus();
    let line48 = generate_line48();
    let (plies, xor, line_xor) = corpus_fingerprint(&games, &line48);
    // Corpus identity lines — CI asserts these equal the Swift harness values.
    println!("CORPUS games={CORPUS_GAMES} plies={plies} xor={xor}");
    println!("CORPUS line48_xor={line_xor}");

    let fen_c = CString::new(START_FEN).unwrap();
    let text_cs: Vec<CString> = texts
        .iter()
        .map(|t| CString::new(t.as_str()).unwrap())
        .collect();
    let star_c = CString::new("*").unwrap();

    // Sanity: FFI perft matches native at the benchmark depth.
    let nodes = Board::startpos().perft(5);
    assert_eq!(nodes, 4_865_609);
    assert_eq!(gigachess_board_perft(&ffi_board_startpos(), 5), nodes);

    let mut g = c.benchmark_group("ffi");

    // 1) perft d5 through the FFI entry (byte-copy + unwind guard included).
    g.throughput(Throughput::Elements(nodes));
    g.bench_function("perft_d5", |b| {
        b.iter_batched(
            ffi_board_startpos,
            |gb| gigachess_board_perft(black_box(&gb), black_box(5)),
            BatchSize::SmallInput,
        )
    });

    // 2) Reference: native perft d5, same machine.
    g.throughput(Throughput::Elements(nodes));
    g.bench_function("perft_d5_native", |b| {
        b.iter_batched(
            Board::startpos,
            |board| board.perft(black_box(5)),
            BatchSize::SmallInput,
        )
    });

    // 3) movegen buffer fill through FFI.
    g.throughput(Throughput::Elements(1));
    g.bench_function("movegen_fill", |b| {
        b.iter_batched(
            || ([0u16; 256], ffi_board_startpos()),
            |(mut buf, gb)| {
                black_box(gigachess_board_legal_moves(
                    black_box(&gb),
                    buf.as_mut_ptr(),
                    buf.len(),
                ))
            },
            BatchSize::SmallInput,
        )
    });

    // 4) 48-ply make/unmake cycle through FFI (Undo as fixed bytes).
    g.throughput(Throughput::Elements(48));
    g.bench_function("play_unmake_48", |b| {
        b.iter_batched(
            || (ffi_board_startpos(), [GigaUndo { bytes: [0; 24] }; 48]),
            |(mut gb, mut undos)| {
                for (i, &w) in black_box(&line48).iter().enumerate() {
                    let st = gigachess_board_play(&mut gb, w, &mut undos[i]);
                    debug_assert_eq!(st, 0);
                }
                for (i, &w) in black_box(&line48).iter().enumerate().rev() {
                    gigachess_board_unmake(&mut gb, w, &undos[i]);
                }
                black_box(gb)
            },
            BatchSize::SmallInput,
        )
    });

    // 5) SAN render ×48 through FFI (advance with unchecked make).
    g.throughput(Throughput::Elements(48));
    g.bench_function("san_48", |b| {
        b.iter_batched(
            || (ffi_board_startpos(), [0i8; 32]),
            |(mut gb, mut out)| {
                for &w in black_box(&line48) {
                    let mut len = 0usize;
                    let st = gigachess_board_move_to_san(
                        &gb,
                        w,
                        out.as_mut_ptr(),
                        out.len(),
                        &mut len,
                    );
                    debug_assert_eq!(st, 0);
                    let mut undo = GigaUndo { bytes: [0; 24] };
                    gigachess_board_make_unchecked(&mut gb, w, &mut undo);
                }
                black_box(gb)
            },
            BatchSize::SmallInput,
        )
    });

    // 6) Zobrist read through FFI (single call, value return).
    g.throughput(Throughput::Elements(1));
    g.bench_function("zobrist", |b| {
        b.iter_batched(
            ffi_board_startpos,
            |gb| gigachess_board_zobrist(black_box(&gb)),
            BatchSize::SmallInput,
        )
    });

    // 7) Codec: parse 40 movetexts through FFI.
    g.throughput(Throughput::Elements(plies as u64));
    g.bench_function("codec_parse", |b| {
        b.iter(|| {
            for t in black_box(&text_cs) {
                let mut out = [0u16; 4096];
                let mut count = 0usize;
                let mut fail = 0usize;
                let st = gigachess_parse_movetext_to_moves2(
                    fen_c.as_ptr(),
                    t.as_ptr(),
                    out.as_mut_ptr(),
                    out.len(),
                    &mut count,
                    &mut fail,
                );
                debug_assert_eq!(st, 0);
                black_box(count);
            }
        })
    });

    // 8) Codec: export 40 word-lists through FFI.
    g.throughput(Throughput::Elements(plies as u64));
    g.bench_function("codec_export", |b| {
        b.iter(|| {
            for words in black_box(&games) {
                let mut out = [0i8; 32768];
                let mut len = 0usize;
                let mut fail = 0usize;
                let st = gigachess_moves2_to_san_movetext(
                    fen_c.as_ptr(),
                    words.as_ptr(),
                    words.len(),
                    star_c.as_ptr(),
                    out.as_mut_ptr(),
                    out.len(),
                    &mut len,
                    &mut fail,
                );
                debug_assert_eq!(st, 0);
                black_box(len);
            }
        })
    });

    // 9) Codec: replay 40 streams through FFI (sequential, per-game).
    g.throughput(Throughput::Elements(plies as u64));
    g.bench_function("codec_replay", |b| {
        b.iter(|| {
            for words in black_box(&games) {
                let mut out = [0u64; 128];
                let mut count = 0usize;
                let mut fail = 0usize;
                let st = gigachess_replay_moves2_stream(
                    fen_c.as_ptr(),
                    words.as_ptr(),
                    words.len(),
                    out.as_mut_ptr(),
                    out.len(),
                    &mut count,
                    &mut fail,
                );
                debug_assert_eq!(st, 0);
                black_box(count);
            }
        })
    });

    // 10) Reference: native sequential replay of the same 40 games.
    g.throughput(Throughput::Elements(plies as u64));
    g.bench_function("codec_replay_native", |b| {
        b.iter(|| {
            for words in black_box(&games) {
                black_box(
                    gigachess::database::replay_moves2_hashes(START_FEN, words).unwrap(),
                );
            }
        })
    });

    g.finish();
}

criterion_group! {
    name = benches;
    config = Criterion::default()
        .warm_up_time(Duration::from_secs(1))
        .measurement_time(Duration::from_secs(2))
        .sample_size(15);
    targets = bench_ffi
}
criterion_main!(benches);
