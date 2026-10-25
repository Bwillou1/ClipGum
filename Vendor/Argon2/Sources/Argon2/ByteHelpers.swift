/// Little-endian byte helpers and the 64-bit rotate-left used by the
/// BLAKE2b / Argon2 ports. All arithmetic in the crypto code uses the
/// wrapping operators (`&+`, `&*`, `&-`) so the code is identical in debug
/// and release builds.

@inline(__always)
func putLE32(_ arr: inout [UInt8], _ offset: Int, _ value: UInt32) {
    arr[offset] = UInt8(value & 0xFF)
    arr[offset + 1] = UInt8((value >> 8) & 0xFF)
    arr[offset + 2] = UInt8((value >> 16) & 0xFF)
    arr[offset + 3] = UInt8((value >> 24) & 0xFF)
}

@inline(__always)
func putLE64(_ arr: inout [UInt8], _ offset: Int, _ value: UInt64) {
    arr[offset] = UInt8(value & 0xFF)
    arr[offset + 1] = UInt8((value >> 8) & 0xFF)
    arr[offset + 2] = UInt8((value >> 16) & 0xFF)
    arr[offset + 3] = UInt8((value >> 24) & 0xFF)
    arr[offset + 4] = UInt8((value >> 32) & 0xFF)
    arr[offset + 5] = UInt8((value >> 40) & 0xFF)
    arr[offset + 6] = UInt8((value >> 48) & 0xFF)
    arr[offset + 7] = UInt8((value >> 56) & 0xFF)
}

@inline(__always)
func leUint64(_ b: [UInt8], _ off: Int) -> UInt64 {
    // ClipGum: split the upstream eight-term expression so Swift 6 can
    // type-check it within the default solver budget. Operations are unchanged.
    let low = UInt64(b[off])
        | (UInt64(b[off + 1]) << 8)
        | (UInt64(b[off + 2]) << 16)
        | (UInt64(b[off + 3]) << 24)
    let high = (UInt64(b[off + 4]) << 32)
        | (UInt64(b[off + 5]) << 40)
        | (UInt64(b[off + 6]) << 48)
        | (UInt64(b[off + 7]) << 56)
    return low | high
}

/// Rotate `v` left by `n` bits. `n` is always in 1...63 in this codebase.
@inline(__always)
func rotl64(_ v: UInt64, _ n: UInt64) -> UInt64 {
    return (v << n) | (v >> (64 - n))
}

extension Array where Element == UInt8 {
    /// Appends `v` as 4 little-endian bytes.
    mutating func appendLE32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}