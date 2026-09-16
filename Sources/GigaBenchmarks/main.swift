// main.swift — Swift-side parity benchmark harness (release only).
//
// Mirrors rust/benches/ffi_parity.rs on an identical deterministic corpus
// (same xorshift seeds, same checked plays, same "*" render), so CI can
// report Swift-vs-native ratios measured on one machine. Prints
// `RESULT <name>=<milliseconds>` lines plus corpus identity lines that CI
// asserts equal to the Rust harness values.
//
// Run: swift run -c release GigaBenchmarks
//
// SPDX-License-Identifier: MIT
import GigaChess

let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
let corpusGames = 40
let corpusMaxPlies = 100
let corpusSeed: UInt64 = 0xBE11_0000_C0DE_0001
let lineSeed: UInt64 = 0x1234_5678_9ABC_DEF0
let perftD5Nodes: UInt64 = 4_865_609

func xorshift(_ state: inout UInt64) -> UInt64 {
    state ^= state &<< 13
    state ^= state &>> 7
    state ^= state &<< 17
    return state
}

/// Deterministic corpus identical to gigachess codec_bench: 40 games of
/// xorshift-picked checked plays, SAN movetexts rendered with `"*"`.
func generateCorpus() -> (texts: [String], games: [[Move]]) {
    var state = corpusSeed
    var texts: [String] = []
    texts.reserveCapacity(corpusGames)
    var games: [[Move]] = []
    games.reserveCapacity(corpusGames)
    for _ in 0..<corpusGames {
        var board = Board()
        var moves: [Move] = []
        for _ in 0..<corpusMaxPlies {
            let legal = board.legalMoves()
            if legal.isEmpty { break }
            let mv = legal[Int(xorshift(&state) % UInt64(legal.count))]
            moves.append(mv)
            try! board.play(mv)
        }
        texts.append(try! Board.sanMovetext(from: moves, startFen: startFEN, result: "*"))
        games.append(moves)
    }
    return (texts, games)
}

/// Deterministic 48-ply startpos line (fixed seed, checked plays).
func generateLine() -> [Move] {
    var board = Board()
    var state = lineSeed
    var out: [Move] = []
    for _ in 0..<48 {
        let legal = board.legalMoves()
        if legal.isEmpty { break }
        let mv = legal[Int(xorshift(&state) % UInt64(legal.count))]
        out.append(mv)
        try! board.play(mv)
    }
    precondition(out.count == 48, "line48 must be a full 48 plies")
    return out
}

/// Median wall time in milliseconds across `rounds` executions.
func medianMs(rounds: Int, _ body: () -> Void) -> Double {
    var samples: [Double] = []
    samples.reserveCapacity(rounds)
    let clock = ContinuousClock()
    for _ in 0..<rounds {
        let d = clock.measure(body)
        samples.append(Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) * 1e-15)
    }
    samples.sort()
    return samples[rounds / 2]
}

// MARK: - Corpus (untimed setup; identity asserted against Rust harness)

let corpus = generateCorpus()
let texts = corpus.texts
let games = corpus.games
let line = generateLine()
let corpusPlies = games.reduce(0) { $0 + $1.count }
var corpusXor: UInt64 = 0
for g in games { for m in g { corpusXor ^= UInt64(m.word) } }
var lineXor: UInt64 = 0
for m in line { lineXor ^= UInt64(m.word) }
precondition(corpusPlies == 4000, "corpus divergence: plies \(corpusPlies)")
precondition(corpusXor == 27715, "corpus divergence: xor \(corpusXor)")
precondition(lineXor == 3971, "line divergence: xor \(lineXor)")
precondition(Board().perft(depth: 5) == perftD5Nodes, "perft d5 mismatch")
print("RESULT corpus_games=\(corpusGames)")
print("RESULT corpus_plies=\(corpusPlies)")
print("RESULT corpus_xor=\(corpusXor)")
print("RESULT corpus_line48_xor=\(lineXor)")

var checksum: UInt64 = 0

// MARK: - Workloads (mirror ffi_parity bench names)

// 1) perft d5 startpos.
let perftMs = medianMs(rounds: 3) { checksum ^= Board().perft(depth: 5) }
print("RESULT perft_d5=\(perftMs)")
print("RESULT perft_d5_ops=1")

// 2) movegen buffer fill (500 fills per round).
let movegenMs = medianMs(rounds: 50) {
    var total = 0
    let b = Board()
    for _ in 0..<500 { b.withLegalMoves { total += $0.count } }
    checksum ^= UInt64(total)
}
print("RESULT movegen_fill=\(movegenMs)")

// 3) 48-ply make/unmake cycle.
let playUnmakeMs = medianMs(rounds: 5000) {
    var b = Board()
    var undos: [Undo] = []
    undos.reserveCapacity(48)
    for m in line { undos.append(b.makeMoveUnchecked(m)) }
    for i in line.indices.reversed() { b.unmake(line[i], undo: undos[i]) }
    checksum ^= b.zobrist
}
print("RESULT play_unmake_48=\(playUnmakeMs)")

// 4) SAN render x48 (advance with unchecked make).
let sanMs = medianMs(rounds: 2000) {
    var b = Board()
    var n = 0
    for m in line {
        n &+= (try! b.san(for: m)).count
        _ = b.makeMoveUnchecked(m)
    }
    checksum ^= UInt64(n)
}
print("RESULT san_48=\(sanMs)")

// 5) Zobrist read x100k.
let zobristMs = medianMs(rounds: 20) {
    let b = Board()
    var acc: UInt64 = 0
    for _ in 0..<100_000 { acc ^= b.zobrist }
    checksum ^= acc
}
print("RESULT zobrist=\(zobristMs)")

// 6) Codec: parse 40 movetexts.
let parseMs = medianMs(rounds: 20) {
    var n = 0
    for t in texts { n += (try! Board.parseMovetextToMoves2(t, from: startFEN)).count }
    checksum ^= UInt64(n)
}
print("RESULT codec_parse=\(parseMs)")

// 7) Codec: export 40 word-lists.
let exportMs = medianMs(rounds: 20) {
    var n = 0
    for g in games { n += (try! Board.sanMovetext(from: g, startFen: startFEN, result: "*")).count }
    checksum ^= UInt64(n)
}
print("RESULT codec_export=\(exportMs)")

// 8) Codec: replay 40 streams.
let replayMs = medianMs(rounds: 50) {
    var n: UInt64 = 0
    for g in games {
        let h = try! Board.replayHashes(moves: g, from: startFEN)
        n ^= UInt64(h.count)
        n ^= h.first ?? 0
    }
    checksum ^= n
}
print("RESULT codec_replay=\(replayMs)")

print("RESULT ops_movegen_fill=500")
print("RESULT ops_play_unmake_48=96")
print("RESULT ops_san_48=48")
print("RESULT ops_zobrist=100000")
print("RESULT ops_codec=40")
print("RESULT checksum=\(checksum)")
