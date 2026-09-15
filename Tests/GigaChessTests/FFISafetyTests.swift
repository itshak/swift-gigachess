// FFISafetyTests.swift — adversarial inputs, layout asserts, no-compat guard.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess
import CGigaChessFFI

final class FFISafetyTests: XCTestCase {
    func testBoardSizeAndOffsets() {
        XCTAssertEqual(MemoryLayout<GigaBoard>.size, 144)
        XCTAssertEqual(MemoryLayout<GigaUndo>.size, 24)
        // Swift-owned mirrors must stay layout-identical (checked Sendable
        // depends on it for sound bridging, no @unchecked anywhere).
        XCTAssertEqual(MemoryLayout<BoardStorage>.size, MemoryLayout<GigaBoard>.size)
        XCTAssertEqual(MemoryLayout<UndoStorage>.size, MemoryLayout<GigaUndo>.size)
        XCTAssertEqual(MemoryLayout<BoardStorage>.alignment, 8)
        XCTAssertEqual(gigachess_board_size_assert(), GIGA_OK)
    }

    func testAdversarialFEN() {
        for bad in ["", "not a fen", "8/8/8/8/8/8/8/8 w - - 0 1", // no kings
                    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0"] {
            XCTAssertThrowsError(try Board(fen: bad), "expected throw for \(bad)")
        }
    }

    func testAdversarialMovesAcrossEntryPoints() throws {
        var board = Board()
        let before = board
        // Garbage words are illegal, never trap.
        for word in [UInt16(0), 0xFFFF, 0x1234, 0x0FFF] {
            XCTAssertFalse(board.isLegal(Move(word: word)))
            XCTAssertThrowsError(try board.play(Move(word: word)))
        }
        XCTAssertEqual(board, before)
        // Garbage SAN never traps.
        for bad in ["", "zzz", "e9", "P@e4", String(repeating: "Q", count: 64)] {
            XCTAssertThrowsError(try board.move(fromSan: bad))
        }
        // Codec garbage reports ply instead of trapping.
        XCTAssertThrowsError(try Board.parseMovetextToMoves2("e4 Qh6 e5", from: BoardTests.startposFEN))
        // check/mate queries on arbitrary positions never trap.
        XCTAssertFalse(Board.empty().isCheckmate)
    }

    func testAllFFISymbolsPresent() {
        // If any of these fail to link, the 1:1 header↔Rust audit drifted.
        XCTAssertEqual(gigachess_board_size_assert(), 0)
        var s = BoardStorage()
        s.withMutableGigaBoard { gigachess_board_startpos($0) }
        let turn: UInt8 = s.withGigaBoard { gigachess_board_turn($0) }
        XCTAssertEqual(turn, 1)
        let n: Int = s.withGigaBoard { gigachess_board_legal_moves($0, nil, 0) }
        XCTAssertEqual(n, 20)
        let key: UInt64 = s.withGigaBoard { gigachess_board_zobrist($0) }
        XCTAssertEqual(key, ZobristTests.expectedStartposKey)
        let perft: UInt64 = s.withGigaBoard { gigachess_board_perft($0, 1) }
        XCTAssertEqual(perft, 20)
    }
}
