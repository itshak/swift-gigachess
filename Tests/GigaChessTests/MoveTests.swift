// MoveTests.swift — Move2 wire fidelity and startpos movegen.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class MoveTests: XCTestCase {
    func testStartposHas20Moves() {
        let board = Board()
        XCTAssertEqual(board.legalMoves().count, 20)
        var count = 0
        board.withLegalMoves { moves in count = moves.count }
        XCTAssertEqual(count, 20)
    }

    func testStartposMoveSet() {
        let board = Board()
        let ucis = Set(board.legalMoves().map(\.uci).sorted())
        // 16 pawn pushes + 4 knight jumps.
        let expected: Set<String> = [
            "a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3", "d2d4",
            "e2e3", "e2e4", "f2f3", "f2f4", "g2g3", "g2g4", "h2h3", "h2h4",
            "b1a3", "b1c3", "g1f3", "g1h3",
        ]
        XCTAssertEqual(ucis, expected)
    }

    func testPackingRoundTripAllWords() {
        // Every 16-bit word preserves from/to; promo nibble 0..4 decodes, 5..15 is none.
        for word in UInt16.min...UInt16.max {
            let m = Move(word: word)
            XCTAssertEqual(m.from, UInt8(word & 0x3F))
            XCTAssertEqual(m.to, UInt8((word >> 6) & 0x3F))
            let promoBits = word >> 12
            if promoBits <= 4, promoBits >= 1 {
                XCTAssertNotNil(m.promotion)
                XCTAssertEqual(m.promotion?.rawValue, promoBits)
            } else {
                XCTAssertNil(m.promotion, "word \(word) promo bits \(promoBits) must be nil")
            }
            XCTAssertEqual(m.word, word)
        }
    }

    func testCastlingWordsVerbatimKingCapturesRook() {
        // e1=4, a1=0, h1=7, e8=60, a8=56, h8=63.
        XCTAssertEqual(Move(from: 4, to: 7).word, 4 | (7 << 6)) // e1h1 = 452
        XCTAssertEqual(Move(from: 4, to: 7).uci, "e1h1")
        XCTAssertEqual(Move(from: 4, to: 0).uci, "e1a1")
        XCTAssertEqual(Move(from: 60, to: 63).uci, "e8h8")
        XCTAssertEqual(Move(from: 60, to: 56).uci, "e8a8")
        XCTAssertEqual(Move(from: 4, to: 7).word, 452)
        XCTAssertEqual(Move(from: 60, to: 63).word, 60 | (63 << 6))
    }

    func testUCIInitAndPromotion() {
        XCTAssertEqual(Move(uci: "e2e4"), Move(from: 12, to: 28))
        XCTAssertEqual(Move(uci: "e7e8q")?.promotion, .queen)
        XCTAssertEqual(Move(uci: "e7e8n")?.promotion, .knight)
        XCTAssertNil(Move(uci: "e2e9"))
        XCTAssertNil(Move(uci: "e2"))
        XCTAssertNil(Move(uci: "e2e4x"))
        // Hashable/Equatable/Sendable basics.
        XCTAssertEqual(Move(word: 1234), Move(word: 1234))
        XCTAssertNotEqual(Move(word: 1234), Move(word: 1235))
        XCTAssertNotNil(Set([Move(word: 1), Move(word: 1), Move(word: 2)]).count == 2 ? 1 : nil)
    }
}
