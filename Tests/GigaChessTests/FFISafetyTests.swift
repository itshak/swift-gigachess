// FFISafetyTests.swift — adversarial inputs, layout asserts, no-compat guard.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess
import CGigaChessFFI

final class FFISafetyTests: XCTestCase {
    func testBoardSizeAndOffsets() {
        XCTAssertEqual(MemoryLayout<GigaBoard>.size, 144)
        XCTAssertEqual(MemoryLayout<GigaUndo>.size, 24)
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
        var b = GigaBoard.zeroed()
        gigachess_board_startpos(&b)
        XCTAssertEqual(gigachess_board_turn(&b), 1)
        XCTAssertEqual(gigachess_board_legal_moves(&b, nil, 0), 20)
        XCTAssertEqual(gigachess_board_zobrist(&b), ZobristTests.expectedStartposKey)
        XCTAssertEqual(gigachess_board_perft(&b, 1), 20)
    }
}
