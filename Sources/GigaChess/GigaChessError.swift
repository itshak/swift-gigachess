// GigaChessError.swift — throws-based error enum for the GigaChess wrapper.
// Maps every C-ABI status code to a Swift error. A chess library never crashes
// its host: panics surface as `.enginePanicked`.
//
// SPDX-License-Identifier: MIT

/// Errors thrown by the GigaChess Swift wrapper.
public enum GigaChessError: Error, Sendable, Hashable, CustomStringConvertible {
    /// FEN string rejected by the engine, with Rust-provided detail when available.
    case invalidFen(String?)
    /// Move is illegal in the current position.
    case illegalMove
    /// SAN string could not be parsed against the position.
    case sanParseFailed(String?)
    /// Caller buffer too small (should not escape to callers; internal guard).
    case bufferTooSmall
    /// Rust panic caught at the FFI boundary.
    case enginePanicked
    /// Movetext/codec/replay failure at the given ply index.
    case codecFailed(ply: Int)

    /// Human-readable description.
    public var description: String {
        switch self {
        case .invalidFen(let detail):
            return "invalid FEN\(detail.map { ": \($0)" } ?? "")"
        case .illegalMove:
            return "illegal move"
        case .sanParseFailed(let token):
            return "SAN parse failed\(token.map { ": \($0)" } ?? "")"
        case .bufferTooSmall:
            return "buffer too small"
        case .enginePanicked:
            return "engine panicked"
        case .codecFailed(let ply):
            return "codec failed at ply \(ply)"
        }
    }
}

extension GigaChessError {
    /// Status codes mirror gigachess_ffi.h.
    static func fromStatus(_ status: Int32, ply: Int? = nil, token: String? = nil) -> GigaChessError? {
        switch status {
        case 0: return nil
        case 1: return .invalidFen(token)
        case 2: return .illegalMove
        case 3: return .sanParseFailed(token)
        case 4: return .bufferTooSmall
        case 5: return .enginePanicked
        case 6: return .codecFailed(ply: ply ?? 0)
        default: return .enginePanicked
        }
    }
}
