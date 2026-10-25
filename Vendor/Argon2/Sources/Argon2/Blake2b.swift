/// A stateful BLAKE2b digest, ported from `golang.org/x/crypto/blake2b`.
///
/// The digest is incremental: `write` buffers full 128-byte blocks and `sum`
/// finalizes the digest without mutating the running state (matching Go's
/// `finalize`, which copies the state before the final block).
final class Blake2b {

    static let blockSize = 128
    static let size512 = 64

    static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    ]

    static let precomputed: [[Int]] = [
        [0, 2, 4, 6, 1, 3, 5, 7, 8, 10, 12, 14, 9, 11, 13, 15],
        [14, 4, 9, 13, 10, 8, 15, 6, 1, 0, 11, 5, 12, 2, 7, 3],
        [11, 12, 5, 15, 8, 0, 2, 13, 10, 3, 7, 9, 14, 6, 1, 4],
        [7, 3, 13, 11, 9, 1, 12, 14, 2, 5, 4, 15, 6, 10, 0, 8],
        [9, 5, 2, 10, 0, 7, 4, 15, 14, 11, 6, 3, 1, 12, 8, 13],
        [2, 6, 0, 8, 12, 10, 11, 3, 4, 7, 15, 1, 13, 5, 14, 9],
        [12, 1, 14, 4, 5, 15, 13, 10, 0, 6, 9, 8, 7, 3, 2, 11],
        [13, 7, 12, 3, 11, 14, 1, 9, 5, 15, 8, 2, 0, 4, 6, 10],
        [6, 14, 11, 0, 15, 9, 3, 8, 12, 13, 1, 10, 2, 7, 4, 5],
        [10, 8, 7, 1, 2, 4, 6, 5, 15, 9, 3, 13, 11, 14, 12, 0],
        [0, 2, 4, 6, 1, 3, 5, 7, 8, 10, 12, 14, 9, 11, 13, 15],
        [14, 4, 9, 13, 10, 8, 15, 6, 1, 0, 11, 5, 12, 2, 7, 3],
    ]

    private var h: [UInt64]
    private var c0: UInt64 = 0
    private var c1: UInt64 = 0
    private let size: Int
    private var block: [UInt8]
    private var offset: Int = 0

    init(size: Int) {
        self.size = size
        self.h = Blake2b.iv
        self.block = [UInt8](repeating: 0, count: Blake2b.blockSize)
        reset()
    }

    func reset() {
        h = Blake2b.iv
        h[0] ^= UInt64(size) | (1 << 16) | (1 << 24)
        offset = 0
        c0 = 0
        c1 = 0
    }

    func write(_ p: [UInt8]) {
        var p = p
        if offset > 0 {
            let remaining = Blake2b.blockSize - offset
            if p.count <= remaining {
                for (i, b) in p.enumerated() {
                    block[offset + i] = b
                }
                offset += p.count
                return
            }
            for i in 0..<remaining {
                block[offset + i] = p[i]
            }
            Blake2b.hashBlocks(&h, &c0, &c1, flag: 0, blocks: block)
            offset = 0
            p = Array(p[remaining...])
        }
        if p.count > Blake2b.blockSize {
            var nn = (p.count / Blake2b.blockSize) * Blake2b.blockSize
            if p.count == nn {
                nn -= Blake2b.blockSize
            }
            Blake2b.hashBlocks(&h, &c0, &c1, flag: 0, blocks: Array(p[0..<nn]))
            p = Array(p[nn...])
        }
        if !p.isEmpty {
            for (i, b) in p.enumerated() {
                block[i] = b
            }
            offset += p.count
        }
    }

    /// Finalizes and returns the digest (first `size` bytes of the 512-bit
    /// state, little-endian). Does not mutate the running state.
    func sum() -> [UInt8] {
        var block = [UInt8](repeating: 0, count: Blake2b.blockSize)
        for i in 0..<offset {
            block[i] = self.block[i]
        }
        var c0 = self.c0
        var c1 = self.c1
        let remaining = UInt64(Blake2b.blockSize - offset)
        if c0 < remaining {
            c1 &-= 1
        }
        c0 &-= remaining
        var h = self.h
        Blake2b.hashBlocks(&h, &c0, &c1, flag: 0xFFFFFFFFFFFFFFFF, blocks: block)
        var out = [UInt8]()
        out.reserveCapacity(size)
        for v in h {
            out.append(UInt8(v & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 32) & 0xFF))
            out.append(UInt8((v >> 40) & 0xFF))
            out.append(UInt8((v >> 48) & 0xFF))
            out.append(UInt8((v >> 56) & 0xFF))
        }
        return Array(out[0..<size])
    }

    /// The BLAKE2b compression function over one or more 128-byte blocks.
    /// `flag` is 0 for intermediate blocks and 0xFFFFFFFFFFFFFFFF for the
    /// final block. `c0`/`c1` are the running byte counters (updated in place).
    static func hashBlocks(_ h: inout [UInt64], _ c0: inout UInt64, _ c1: inout UInt64,
                           flag: UInt64, blocks: [UInt8]) {
        var i = 0
        while i < blocks.count {
            c0 &+= 128
            if c0 < 128 {
                c1 &+= 1
            }
            var v = [UInt64](repeating: 0, count: 16)
            v[0] = h[0]; v[1] = h[1]; v[2] = h[2]; v[3] = h[3]
            v[4] = h[4]; v[5] = h[5]; v[6] = h[6]; v[7] = h[7]
            v[8] = iv[0]; v[9] = iv[1]; v[10] = iv[2]; v[11] = iv[3]
            v[12] = iv[4] ^ c0
            v[13] = iv[5] ^ c1
            v[14] = iv[6] ^ flag
            v[15] = iv[7]
            var m = [UInt64](repeating: 0, count: 16)
            for j in 0..<16 {
                m[j] = leUint64(blocks, i)
                i += 8
            }
            for round in 0..<12 {
                let s = precomputed[round]
                g(&v, 0, 4, 8, 12, m[s[0]], m[s[4]])
                g(&v, 1, 5, 9, 13, m[s[1]], m[s[5]])
                g(&v, 2, 6, 10, 14, m[s[2]], m[s[6]])
                g(&v, 3, 7, 11, 15, m[s[3]], m[s[7]])
                g(&v, 0, 5, 10, 15, m[s[8]], m[s[12]])
                g(&v, 1, 6, 11, 12, m[s[9]], m[s[13]])
                g(&v, 2, 7, 8, 13, m[s[10]], m[s[14]])
                g(&v, 3, 4, 9, 14, m[s[11]], m[s[15]])
            }
            h[0] ^= v[0] ^ v[8]
            h[1] ^= v[1] ^ v[9]
            h[2] ^= v[2] ^ v[10]
            h[3] ^= v[3] ^ v[11]
            h[4] ^= v[4] ^ v[12]
            h[5] ^= v[5] ^ v[13]
            h[6] ^= v[6] ^ v[14]
            h[7] ^= v[7] ^ v[15]
        }
    }

    /// The BLAKE2b `G` mixing function.
    static func g(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int,
                  _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = rotl64(v[d] ^ v[a], 32)
        v[c] = v[c] &+ v[d]
        v[b] = rotl64(v[b] ^ v[c], 40)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = rotl64(v[d] ^ v[a], 48)
        v[c] = v[c] &+ v[d]
        v[b] = rotl64(v[b] ^ v[c], 1)
    }

    /// BLAKE2X-style extended-length hash used by Argon2 to derive the
    /// `outLen`-byte key from a 1024-byte block. Ported from
    /// `golang.org/x/crypto/argon2/blake2b.go`.
    static func blake2bHash(outLen: Int, _ input: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: outLen)
        var b2: Blake2b
        if outLen < Blake2b.size512 {
            b2 = Blake2b(size: outLen)
        } else {
            b2 = Blake2b(size: Blake2b.size512)
        }
        var buffer = [UInt8](repeating: 0, count: 4)
        putLE32(&buffer, 0, UInt32(outLen))
        b2.write(buffer)
        b2.write(input)
        if outLen <= Blake2b.size512 {
            let digest = b2.sum()
            for i in 0..<outLen {
                out[i] = digest[i]
            }
            return out
        }
        let total = outLen
        buffer = b2.sum()
        b2.reset()
        for i in 0..<32 {
            out[i] = buffer[i]
        }
        var outOffset = 32
        while total - outOffset > Blake2b.size512 {
            b2.write(buffer)
            buffer = b2.sum()
            for i in 0..<32 {
                out[outOffset + i] = buffer[i]
            }
            outOffset += 32
            b2.reset()
        }
        if total % Blake2b.size512 > 0 {
            let r = ((total + 31) / 32) - 2
            b2 = Blake2b(size: total - 32 * r)
        }
        b2.write(buffer)
        let finalDigest = b2.sum()
        let remaining = total - outOffset
        for i in 0..<remaining {
            out[outOffset + i] = finalDigest[i]
        }
        return out
    }
}