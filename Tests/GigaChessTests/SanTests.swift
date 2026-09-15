// SanTests.swift — SAN render/parse, disambiguation, castling spellings.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class SanTests: XCTestCase {
    func testRenderBasics() throws {
        let board = Board()
        XCTAssertEqual(try board.san(for: Move(from: 12, to: 28)), "e4")
        XCTAssertEqual(try board.san(for: Move(from: 6, to: 21)), "Nf3") // g1f3
        // Capture with check suffix shape: scholar's Qxf7# tested in PlayTests;
        // here just verify a pawn capture renders with file + x.
        var b = Board()
        try b.playSan("e4", "d5")
        XCTAssertEqual(try b.san(for: b.move(fromSan: "exd5")), "exd5")
    }

    func testParseRoundTrip() throws {
        var board = Board()
        let sans = ["e4", "e5", "Nf3", "Nc6", "Bb5"]
        for san in sans {
            let mv = try board.move(fromSan: san)
            XCTAssertEqual(try board.san(for: mv), san, "round-trip failed for \(san)")
            _ = try board.play(mv)
        }
    }

    func testDisambiguation() throws {
        // Knights on c3+e3 both hit d5: file disambiguation (Ncd5 / Ned5).
        let board = try Board(fen: "4k3/8/8/8/8/2N1N3/8/4K3 w - - 0 1")
        let c3d5 = Move(from: 18, to: 35) // c3=18, d5=35
        let e3d5 = Move(from: 20, to: 35) // e3=20
        XCTAssertEqual(try board.san(for: c3d5), "Ncd5")
        XCTAssertEqual(try board.san(for: e3d5), "Ned5")
        XCTAssertEqual(try board.move(fromSan: "Ncd5"), c3d5)
        XCTAssertEqual(try board.move(fromSan: "Ned5"), e3d5)
    }

    func testCastlingOOAndZeroZeroAccepted() throws {
        // Cleared back rank with full rights: both castlings legal.
        let board = try Board(fen: "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1")
        let oo = try board.move(fromSan: "O-O")
        let zero = try board.move(fromSan: "0-0")
        XCTAssertEqual(oo, zero)
        XCTAssertEqual(oo.uci, "e1h1")
        XCTAssertEqual(try board.san(for: oo), "O-O")
        // Queenside too.
        XCTAssertEqual(try board.move(fromSan: "O-O-O").uci, "e1a1")
        XCTAssertEqual(try board.move(fromSan: "0-0-0").uci, "e1a1")
    }

    func testInvalidSanThrows() {
        let board = Board()
        XCTAssertThrowsError(try board.move(fromSan: "Qh6")) // blocked queen
        XCTAssertThrowsError(try board.move(fromSan: ""))
        XCTAssertThrowsError(try board.move(fromSan: "zzz"))
    }

    func testPlaySanErrorPly() {
        var board = Board()
        XCTAssertThrowsError(try board.playSan(["e4", "e5", "Qh6"])) { error in
            XCTAssertEqual(error as? GigaChessError, GigaChessError.codecFailed(ply: 2))
        }
    }

    func testMoveInitParsing() throws {
        let board = Board()
        XCTAssertEqual(try Move(parsing: "e4", on: board), Move(from: 12, to: 28))
    }
}
