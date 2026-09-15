// Board.swift — value-type chess position over the native `gigachess` engine.
// `Board` is a Swift struct holding the 144-byte Copy Rust board by value:
// assignment and parameter passing snapshot bit-for-bit (search-stack safe).
// No heap allocation, no deinit/free, no opaque-pointer handles.
//
// Hot paths are zero-alloc: `withLegalMoves` (visitor), caller-owned FEN/SAN
// buffers, UInt64-by-value Zobrist. `legalMoves()` allocates and is documented
// as the cold-path convenience.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

/// Side to move. Raw values match the engine (Black = 0, White = 1).
public enum Color: UInt8, Sendable, Hashable, CustomStringConvertible {
    case black = 0
    case white = 1

    public var description: String { self == .white ? "w" : "b" }

    public var other: Color { self == .white ? .black : .white }
}

/// Piece role. Discriminants match the moves2 promo nibble
/// (0 = pawn/none, 1 = N, 2 = B, 3 = R, 4 = Q, 5 = king).
public enum Role: UInt8, Sendable, Hashable, CustomStringConvertible {
    case pawn = 0
    case knight = 1
    case bishop = 2
    case rook = 3
    case queen = 4
    case king = 5

    public var description: String {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
}

/// A colored piece.
public struct Piece: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let color: Color
    public let role: Role

    public init(color: Color, role: Role) {
        self.color = color
        self.role = role
    }

    /// Mailbox code (color * 6 + role): Black 0…5, White 6…11.
    var code: UInt8 { color.rawValue * 6 + role.rawValue }

    static func fromCode(_ code: Int32) -> Piece? {
        guard (0..<12).contains(code) else { return nil }
        let color: Color = code >= 6 ? .white : .black
        guard let role = Role(rawValue: UInt8(code % 6)) else { return nil }
        return Piece(color: color, role: role)
    }

    public var description: String {
        let c = role.description
        return color == .white ? c : c.lowercased()
    }
}

/// A chess position (144-byte value snapshot).
public struct Board: Sendable {
    var storage: GigaBoard

    // MARK: - Construction

    init(storage: GigaBoard) {
        self.storage = storage
    }

    /// The standard starting position.
    public init() {
        var s = GigaBoard.zeroed()
        gigachess_board_startpos(&s)
        self.storage = s
    }

    /// The standard starting position (explicit spelling).
    public static func startpos() -> Board { Board() }

    /// Empty board, White to move.
    public static func empty() -> Board {
        var s = GigaBoard.zeroed()
        gigachess_board_empty(&s)
        return Board(storage: s)
    }

    /// Parse a FEN string. Throws `GigaChessError.invalidFen` (with engine
    /// detail when available) instead of trapping.
    public init(fen: String) throws {
        var s = GigaBoard.zeroed()
        var detail: String?
        let status: Int32 = fen.withCString { fenPtr in
            withUnsafeTemporaryAllocation(of: CChar.self, capacity: 256) { errBuf in
                guard let base = errBuf.baseAddress else { return GIGA_E_PANICKED }
                let st = gigachess_board_from_fen(&s, fenPtr, base, errBuf.count)
                if st != GIGA_OK, base.pointee != 0 {
                    detail = String(cString: base)
                }
                return st
            }
        }
        if status != GIGA_OK {
            if status == GIGA_E_INVALID_FEN { throw GigaChessError.invalidFen(detail) }
            if let err = GigaChessError.fromStatus(status) { throw err }
            throw GigaChessError.enginePanicked
        }
        self.storage = s
    }

    // MARK: - Queries

    /// Side to move.
    public var turn: Color {
        var copy = storage
        let raw = gigachess_board_turn(&copy)
        return Color(rawValue: raw) ?? .white
    }

    /// Piece on a square (0 = a1 … 63 = h8), or nil when empty.
    public func piece(at square: UInt8) -> Piece? {
        precondition(square < 64, "square out of range")
        var copy = storage
        let code = gigachess_board_piece_at(&copy, square)
        if code == 12 { return nil }
        return Piece.fromCode(code)
    }

    /// King square for a color.
    public func kingSquare(_ color: Color) -> UInt8 {
        var copy = storage
        return gigachess_board_king_square(&copy, color.rawValue)
    }

    /// Castling-rights bitmask (bit0 WK, bit1 WQ, bit2 BK, bit3 BQ).
    public var castlingRights: UInt8 {
        var copy = storage
        return gigachess_board_castling_rights(&copy)
    }

    /// En-passant square, or nil when none.
    public var enPassant: UInt8? {
        var copy = storage
        let ep = gigachess_board_en_passant(&copy)
        if ep < 0 { return nil }
        return UInt8(ep)
    }

    /// Halfmove clock.
    public var halfmoveClock: UInt16 {
        var half: UInt16 = 0
        var full: UInt16 = 0
        var copy = storage
        gigachess_board_clocks(&copy, &half, &full)
        return half
    }

    /// Fullmove number.
    public var fullmoveNumber: UInt16 {
        var half: UInt16 = 0
        var full: UInt16 = 0
        var copy = storage
        gigachess_board_clocks(&copy, &half, &full)
        return full
    }

    /// Export FEN (canonical form, incl. EP normalization). Throws only on
    /// engine panic; the 96-byte caller buffer always suffices for valid input.
    public func fen() throws -> String {
        var copy = storage
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: 128) { buf in
            guard let base = buf.baseAddress else { throw GigaChessError.enginePanicked }
            var outLen = 0
            let status = gigachess_board_to_fen(&copy, base, buf.count, &outLen)
            if let err = GigaChessError.fromStatus(status) { throw err }
            return String(cString: base)
        }
    }

    /// True when the side to move is in check.
    public var isCheck: Bool {
        var copy = storage
        return gigachess_board_in_check(&copy) != 0
    }

    /// True when the side to move is checkmated (in check, no legal moves).
    /// Zero-alloc: asks the engine for the move count without materializing moves.
    public var isCheckmate: Bool {
        guard isCheck else { return false }
        var copy = storage
        return gigachess_board_legal_moves(&copy, nil, 0) == 0
    }

    /// True on stalemate (no legal moves, not in check). Zero-alloc.
    public var isStalemate: Bool {
        guard !isCheck else { return false }
        var copy = storage
        return gigachess_board_legal_moves(&copy, nil, 0) == 0
    }

    // MARK: - Movegen

    /// True when the move is legal in this position.
    public func isLegal(_ move: Move) -> Bool {
        var copy = storage
        return gigachess_board_is_legal(&copy, move.word) != 0
    }

    /// Play a legal move, returning its Undo token. Throws
    /// `GigaChessError.illegalMove` with the board unchanged on illegal input.
    @discardableResult
    public mutating func play(_ move: Move) throws -> Undo {
        var undoStorage = GigaUndo.zeroed()
        let status = gigachess_board_play(&storage, move.word, &undoStorage)
        if let err = GigaChessError.fromStatus(status) { throw err }
        return Undo(storage: undoStorage)
    }

    /// Unchecked make for search (caller guarantees legality).
    public mutating func makeMoveUnchecked(_ move: Move) -> Undo {
        var undoStorage = GigaUndo.zeroed()
        gigachess_board_make_unchecked(&storage, move.word, &undoStorage)
        return Undo(storage: undoStorage)
    }

    /// Unmake a move made with `play` or `makeMoveUnchecked`.
    public mutating func unmake(_ move: Move, undo: Undo) {
        var undoCopy = undo.storage
        gigachess_board_unmake(&storage, move.word, &undoCopy)
    }

    /// Hot-path visitor: enumerates legal moves with no Swift heap allocation
    /// (caller stack buffer of 256 words, mirroring native generate_visitor).
    public func withLegalMoves<R>(_ body: (UnsafeBufferPointer<Move>) throws -> R) rethrows -> R {
        try withUnsafeTemporaryAllocation(of: UInt16.self, capacity: 256) { words in
            guard let base = words.baseAddress else {
                return try body(UnsafeBufferPointer(start: nil, count: 0))
            }
            var copy = storage
            let count = gigachess_board_legal_moves(&copy, base, words.count)
            let n = min(count, words.count)
            return try base.withMemoryRebound(to: Move.self, capacity: n) { moveBase in
                let buf = UnsafeBufferPointer(start: moveBase, count: n)
                return try body(buf)
            }
        }
    }

    /// Cold-path convenience: returns allocated `[Move]`. For hot loops use
    /// `withLegalMoves` instead (documented allocation).
    public func legalMoves() -> [Move] {
        withLegalMoves { Array($0) }
    }

    /// Perft node count (identical to native Rust perft at every depth).
    public func perft(depth: UInt32) -> UInt64 {
        var copy = storage
        return gigachess_board_perft(&copy, depth)
    }
}

// MARK: - Equatable (bit-for-bit incl. hash)

extension Board: Equatable {
    public static func == (lhs: Board, rhs: Board) -> Bool {
        withUnsafeBytes(of: lhs.storage) { l in
            withUnsafeBytes(of: rhs.storage) { r in
                l.elementsEqual(r)
            }
        }
    }
}

extension Board: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Hash via the Zobrist key (incrementally maintained, bit-exact).
        hasher.combine(zobrist)
    }
}
