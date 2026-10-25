/// The Argon2 core engine — a byte-for-byte port of `golang.org/x/crypto/argon2`.
///
/// Unlike the totp-swift port, this engine supports the optional secret key
/// (`K`) and associated data (`X`) inputs and all three variants (argon2d,
/// argon2i, argon2id), which is required to run the RFC 9106 test vectors.
/// All arithmetic uses the wrapping operators so debug and release builds are
/// identical.
enum Argon2Engine {

    static let version: UInt32 = 0x13
    static let blockLength = 128
    static let syncPoints = 4

    static let argon2d = 0
    static let argon2i = 1
    static let argon2id = 2

    /// Derives a `keyLen`-byte tag using the given variant.
    static func derive(password: [UInt8], salt: [UInt8], secret: [UInt8], ad: [UInt8],
                       time: UInt32, memory: UInt32, threads: UInt32, keyLen: UInt32,
                       mode: Int) -> [UInt8] {
        var h0 = initHash(password: password, salt: salt, secret: secret, ad: ad,
                          time: time, memory: memory, threads: threads, keyLen: keyLen,
                          mode: mode)
        var mem = memory
        let sync = UInt32(syncPoints)
        mem = (mem / (sync &* threads)) &* (sync &* threads)
        if mem < 2 &* sync &* threads {
            mem = 2 &* sync &* threads
        }
        var B = initBlocks(&h0, memory: mem, threads: threads)
        processBlocks(&B, time: time, memory: mem, threads: threads, mode: mode)
        return extractKey(&B, memory: Int(mem), threads: Int(threads), keyLen: Int(keyLen))
    }

    /// Returns the 64-byte pre-hashing digest `H_0` (RFC 9106 Figure 1).
    static func h0Digest(password: [UInt8], salt: [UInt8], secret: [UInt8], ad: [UInt8],
                         time: UInt32, memory: UInt32, threads: UInt32, keyLen: UInt32,
                         mode: Int) -> [UInt8] {
        let h0 = initHash(password: password, salt: salt, secret: secret, ad: ad,
                          time: time, memory: memory, threads: threads, keyLen: keyLen,
                          mode: mode)
        return Array(h0[0..<Blake2b.size512])
    }

    // MARK: - Setup

    static func initHash(password: [UInt8], salt: [UInt8], secret: [UInt8], ad: [UInt8],
                         time: UInt32, memory: UInt32, threads: UInt32, keyLen: UInt32,
                         mode: Int) -> [UInt8] {
        let b2 = Blake2b(size: Blake2b.size512)
        var params: [UInt8] = []
        params.appendLE32(threads)
        params.appendLE32(keyLen)
        params.appendLE32(memory)
        params.appendLE32(time)
        params.appendLE32(version)
        params.appendLE32(UInt32(mode))
        b2.write(params)
        var tmp = [UInt8](repeating: 0, count: 4)
        putLE32(&tmp, 0, UInt32(password.count))
        b2.write(tmp)
        b2.write(password)
        putLE32(&tmp, 0, UInt32(salt.count))
        b2.write(tmp)
        b2.write(salt)
        putLE32(&tmp, 0, UInt32(secret.count))
        b2.write(tmp)
        b2.write(secret)
        putLE32(&tmp, 0, UInt32(ad.count))
        b2.write(tmp)
        b2.write(ad)
        let digest = b2.sum()
        var h0 = [UInt8](repeating: 0, count: Blake2b.size512 + 8)
        for i in 0..<Blake2b.size512 {
            h0[i] = digest[i]
        }
        return h0
    }

    /// Returns the flat memory as `memory * 128` little-endian words.
    static func initBlocks(_ h0: inout [UInt8], memory: UInt32, threads: UInt32) -> [UInt64] {
        let count = Int(memory)
        var B = [UInt64](repeating: 0, count: count * blockLength)
        for lane in 0..<Int(threads) {
            let j = lane * (count / Int(threads))
            putLE32(&h0, Blake2b.size512 + 4, UInt32(lane))
            putLE32(&h0, Blake2b.size512, 0)
            let block0 = Blake2b.blake2bHash(outLen: 1024, h0)
            for i in 0..<blockLength {
                B[j * blockLength + i] = leUint64(block0, i * 8)
            }
            putLE32(&h0, Blake2b.size512, 1)
            let block1 = Blake2b.blake2bHash(outLen: 1024, h0)
            for i in 0..<blockLength {
                B[(j + 1) * blockLength + i] = leUint64(block1, i * 8)
            }
        }
        return B
    }

    // MARK: - Main loop

    static func processBlocks(_ B: inout [UInt64], time: UInt32, memory: UInt32,
                              threads: UInt32, mode: Int) {
        let lanes = Int(memory) / Int(threads)
        let segments = lanes / syncPoints
        for n in 0..<Int(time) {
            for slice in 0..<syncPoints {
                for lane in 0..<Int(threads) {
                    processSegment(&B, n: n, slice: slice, lane: lane, lanes: lanes,
                                   segments: segments, memory: Int(memory),
                                   time: Int(time), threads: Int(threads), mode: mode)
                }
            }
        }
    }

    static func processSegment(_ B: inout [UInt64], n: Int, slice: Int, lane: Int,
                               lanes: Int, segments: Int, memory: Int, time: Int,
                               threads: Int, mode: Int) {
        var addresses = [UInt64](repeating: 0, count: blockLength)
        var inBlock = [UInt64](repeating: 0, count: blockLength)
        let zero = [UInt64](repeating: 0, count: blockLength)
        let useDataIndependent = (mode == argon2i) || (mode == argon2id && n == 0 && slice < syncPoints / 2)
        if useDataIndependent {
            inBlock[0] = UInt64(n)
            inBlock[1] = UInt64(lane)
            inBlock[2] = UInt64(slice)
            inBlock[3] = UInt64(memory)
            inBlock[4] = UInt64(time)
            inBlock[5] = UInt64(mode)
        }
        var index = 0
        if n == 0 && slice == 0 {
            index = 2
            if mode == argon2i || mode == argon2id {
                inBlock[6] &+= 1
                processBlockStandalone(&addresses, inBlock, zero)
                processBlockStandalone(&addresses, addresses, zero)
            }
        }
        var offset = lane * lanes + slice * segments + index
        var random: UInt64 = 0
        while index < segments {
            var prev = offset - 1
            if index == 0 && slice == 0 {
                prev += lanes
            }
            if useDataIndependent {
                if index % blockLength == 0 {
                    inBlock[6] &+= 1
                    processBlockStandalone(&addresses, inBlock, zero)
                    processBlockStandalone(&addresses, addresses, zero)
                }
                random = addresses[index % blockLength]
            } else {
                random = B[prev * blockLength]
            }
            let newOffset = indexAlpha(random, lanes: lanes, segments: segments,
                                       threads: threads, n: n, slice: slice,
                                       lane: lane, index: index)
            processBlockXORFlat(&B, offset, prev, newOffset)
            index += 1
            offset += 1
        }
    }

    static func extractKey(_ B: inout [UInt64], memory: Int, threads: Int, keyLen: Int) -> [UInt8] {
        let lanes = memory / threads
        let finalBlock = (memory - 1) * blockLength
        for lane in 0..<(threads - 1) {
            let lastOfLane = (lane * lanes + lanes - 1) * blockLength
            for i in 0..<blockLength {
                B[finalBlock + i] ^= B[lastOfLane + i]
            }
        }
        var block = [UInt8](repeating: 0, count: 1024)
        for i in 0..<blockLength {
            putLE64(&block, i * 8, B[finalBlock + i])
        }
        return Blake2b.blake2bHash(outLen: keyLen, block)
    }

    // MARK: - Index selection

    static func indexAlpha(_ rand: UInt64, lanes: Int, segments: Int, threads: Int,
                           n: Int, slice: Int, lane: Int, index: Int) -> Int {
        var refLane = Int((rand >> 32) % UInt64(threads))
        if n == 0 && slice == 0 {
            refLane = lane
        }
        var m = 3 * segments
        var s = ((slice + 1) % syncPoints) * segments
        if lane == refLane {
            m += index
        }
        if n == 0 {
            m = slice * segments
            s = 0
            if slice == 0 || lane == refLane {
                m += index
            }
        }
        if index == 0 || lane == refLane {
            m -= 1
        }
        return phi(rand, m: UInt64(m), s: UInt64(s), lane: refLane, lanes: lanes)
    }

    static func phi(_ rand: UInt64, m: UInt64, s: UInt64, lane: Int, lanes: Int) -> Int {
        var p = rand & 0xFFFFFFFF
        p = (p &* p) >> 32
        p = (p &* m) >> 32
        return lane * lanes + Int((s &+ m &- (p &+ 1)) % UInt64(lanes))
    }

    // MARK: - BLAMKA

    /// `out = in1 ^ in2 ^ G'(in1 ^ in2)`, where `G'` is the BLAMKA mixing
    /// function. Operates on standalone 128-word blocks (used for the
    /// data-independent address cache).
    static func processBlockStandalone(_ out: inout [UInt64], _ in1: [UInt64], _ in2: [UInt64]) {
        var t = [UInt64](repeating: 0, count: blockLength)
        for i in 0..<blockLength {
            t[i] = in1[i] ^ in2[i]
        }
        applyBlamka(&t)
        for i in 0..<blockLength {
            out[i] = in1[i] ^ in2[i] ^ t[i]
        }
    }

    /// `B[out] ^= B[in1] ^ B[in2] ^ G'(B[in1] ^ B[in2])` on the flat memory
    /// (Go `processBlockXOR`, accumulate).
    static func processBlockXORFlat(_ B: inout [UInt64], _ out: Int, _ in1: Int, _ in2: Int) {
        var t = [UInt64](repeating: 0, count: blockLength)
        for i in 0..<blockLength {
            t[i] = B[in1 * blockLength + i] ^ B[in2 * blockLength + i]
        }
        applyBlamka(&t)
        for i in 0..<blockLength {
            B[out * blockLength + i] ^= B[in1 * blockLength + i] ^ B[in2 * blockLength + i] ^ t[i]
        }
    }

    /// Applies the full BLAMKA transformation to a 128-word block: eight
    /// consecutive 16-word column groups, then eight strided row groups.
    static func applyBlamka(_ t: inout [UInt64]) {
        for base in stride(from: 0, to: blockLength, by: 16) {
            var group = [UInt64](repeating: 0, count: 16)
            for j in 0..<16 {
                group[j] = t[base + j]
            }
            blamkaGeneric(&group)
            for j in 0..<16 {
                t[base + j] = group[j]
            }
        }
        for i in stride(from: 0, to: blockLength / 8, by: 2) {
            var group = [UInt64](repeating: 0, count: 16)
            group[0] = t[i]; group[1] = t[i + 1]
            group[2] = t[16 + i]; group[3] = t[16 + i + 1]
            group[4] = t[32 + i]; group[5] = t[32 + i + 1]
            group[6] = t[48 + i]; group[7] = t[48 + i + 1]
            group[8] = t[64 + i]; group[9] = t[64 + i + 1]
            group[10] = t[80 + i]; group[11] = t[80 + i + 1]
            group[12] = t[96 + i]; group[13] = t[96 + i + 1]
            group[14] = t[112 + i]; group[15] = t[112 + i + 1]
            blamkaGeneric(&group)
            t[i] = group[0]; t[i + 1] = group[1]
            t[16 + i] = group[2]; t[16 + i + 1] = group[3]
            t[32 + i] = group[4]; t[32 + i + 1] = group[5]
            t[48 + i] = group[6]; t[48 + i + 1] = group[7]
            t[64 + i] = group[8]; t[64 + i + 1] = group[9]
            t[80 + i] = group[10]; t[80 + i + 1] = group[11]
            t[96 + i] = group[12]; t[96 + i + 1] = group[13]
            t[112 + i] = group[14]; t[112 + i + 1] = group[15]
        }
    }

    /// The BLAMKA mixing function over 16 words. Ported verbatim from
    /// `golang.org/x/crypto/argon2/blamka_generic.go`.
    @inline(__always)
    static func blamkaGeneric(_ t: inout [UInt64]) {
        var v00 = t[0], v01 = t[1], v02 = t[2], v03 = t[3]
        var v04 = t[4], v05 = t[5], v06 = t[6], v07 = t[7]
        var v08 = t[8], v09 = t[9], v10 = t[10], v11 = t[11]
        var v12 = t[12], v13 = t[13], v14 = t[14], v15 = t[15]

        v00 = v00 &+ v04 &+ blamkaMul(v00, v04)
        v12 ^= v00
        v12 = rotl64(v12, 32)
        v08 = v08 &+ v12 &+ blamkaMul(v08, v12)
        v04 ^= v08
        v04 = rotl64(v04, 40)

        v00 = v00 &+ v04 &+ blamkaMul(v00, v04)
        v12 ^= v00
        v12 = rotl64(v12, 48)
        v08 = v08 &+ v12 &+ blamkaMul(v08, v12)
        v04 ^= v08
        v04 = rotl64(v04, 1)

        v01 = v01 &+ v05 &+ blamkaMul(v01, v05)
        v13 ^= v01
        v13 = rotl64(v13, 32)
        v09 = v09 &+ v13 &+ blamkaMul(v09, v13)
        v05 ^= v09
        v05 = rotl64(v05, 40)

        v01 = v01 &+ v05 &+ blamkaMul(v01, v05)
        v13 ^= v01
        v13 = rotl64(v13, 48)
        v09 = v09 &+ v13 &+ blamkaMul(v09, v13)
        v05 ^= v09
        v05 = rotl64(v05, 1)

        v02 = v02 &+ v06 &+ blamkaMul(v02, v06)
        v14 ^= v02
        v14 = rotl64(v14, 32)
        v10 = v10 &+ v14 &+ blamkaMul(v10, v14)
        v06 ^= v10
        v06 = rotl64(v06, 40)

        v02 = v02 &+ v06 &+ blamkaMul(v02, v06)
        v14 ^= v02
        v14 = rotl64(v14, 48)
        v10 = v10 &+ v14 &+ blamkaMul(v10, v14)
        v06 ^= v10
        v06 = rotl64(v06, 1)

        v03 = v03 &+ v07 &+ blamkaMul(v03, v07)
        v15 ^= v03
        v15 = rotl64(v15, 32)
        v11 = v11 &+ v15 &+ blamkaMul(v11, v15)
        v07 ^= v11
        v07 = rotl64(v07, 40)

        v03 = v03 &+ v07 &+ blamkaMul(v03, v07)
        v15 ^= v03
        v15 = rotl64(v15, 48)
        v11 = v11 &+ v15 &+ blamkaMul(v11, v15)
        v07 ^= v11
        v07 = rotl64(v07, 1)

        v00 = v00 &+ v05 &+ blamkaMul(v00, v05)
        v15 ^= v00
        v15 = rotl64(v15, 32)
        v10 = v10 &+ v15 &+ blamkaMul(v10, v15)
        v05 ^= v10
        v05 = rotl64(v05, 40)

        v00 = v00 &+ v05 &+ blamkaMul(v00, v05)
        v15 ^= v00
        v15 = rotl64(v15, 48)
        v10 = v10 &+ v15 &+ blamkaMul(v10, v15)
        v05 ^= v10
        v05 = rotl64(v05, 1)

        v01 = v01 &+ v06 &+ blamkaMul(v01, v06)
        v12 ^= v01
        v12 = rotl64(v12, 32)
        v11 = v11 &+ v12 &+ blamkaMul(v11, v12)
        v06 ^= v11
        v06 = rotl64(v06, 40)

        v01 = v01 &+ v06 &+ blamkaMul(v01, v06)
        v12 ^= v01
        v12 = rotl64(v12, 48)
        v11 = v11 &+ v12 &+ blamkaMul(v11, v12)
        v06 ^= v11
        v06 = rotl64(v06, 1)

        v02 = v02 &+ v07 &+ blamkaMul(v02, v07)
        v13 ^= v02
        v13 = rotl64(v13, 32)
        v08 = v08 &+ v13 &+ blamkaMul(v08, v13)
        v07 ^= v08
        v07 = rotl64(v07, 40)

        v02 = v02 &+ v07 &+ blamkaMul(v02, v07)
        v13 ^= v02
        v13 = rotl64(v13, 48)
        v08 = v08 &+ v13 &+ blamkaMul(v08, v13)
        v07 ^= v08
        v07 = rotl64(v07, 1)

        v03 = v03 &+ v04 &+ blamkaMul(v03, v04)
        v14 ^= v03
        v14 = rotl64(v14, 32)
        v09 = v09 &+ v14 &+ blamkaMul(v09, v14)
        v04 ^= v09
        v04 = rotl64(v04, 40)

        v03 = v03 &+ v04 &+ blamkaMul(v03, v04)
        v14 ^= v03
        v14 = rotl64(v14, 48)
        v09 = v09 &+ v14 &+ blamkaMul(v09, v14)
        v04 ^= v09
        v04 = rotl64(v04, 1)

        t[0] = v00; t[1] = v01; t[2] = v02; t[3] = v03
        t[4] = v04; t[5] = v05; t[6] = v06; t[7] = v07
        t[8] = v08; t[9] = v09; t[10] = v10; t[11] = v11
        t[12] = v12; t[13] = v13; t[14] = v14; t[15] = v15
    }

    /// `2 * (a mod 2^32) * (b mod 2^32)`, wrapping on overflow (matches Go's
    /// `2*uint64(uint32(a))*uint64(uint32(b))`).
    @inline(__always)
    static func blamkaMul(_ a: UInt64, _ b: UInt64) -> UInt64 {
        return 2 &* UInt64(UInt32(truncatingIfNeeded: a)) &* UInt64(UInt32(truncatingIfNeeded: b))
    }
}