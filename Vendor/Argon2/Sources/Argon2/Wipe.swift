import Foundation

/// Overwrites sensitive bytes with zeros.
///
/// The buffer is an `inout` array, so each write is an observable mutation of
/// the caller's storage and cannot be elided by optimization.
func wipe(_ bytes: inout [UInt8]) {
    for i in bytes.indices {
        bytes[i] = 0
    }
}