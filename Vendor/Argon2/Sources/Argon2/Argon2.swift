import Foundation
import Security

/// The public Argon2 API (RFC 9106).
///
/// ```swift
/// let params = Argon2Params(timeCost: 3, memoryCostKilobytes: 65536, parallelism: 4)
/// let salt = Argon2.randomSalt()
/// let tag = try Argon2.deriveKey(password: "hunter2".data(using: .utf8)!,
///                                salt: salt, params: params)
/// let ok = try Argon2.verify(password: "hunter2".data(using: .utf8)!,
///                            expected: tag, salt: salt, params: params)
/// ```
public enum Argon2 {

    /// Derives a key (tag) of length `params.outputLength` bytes.
    ///
    /// - Parameters:
    ///   - password: The password bytes.
    ///   - salt: The salt bytes.
    ///   - secret: Optional secret key (RFC 9106 `K`). Empty by default.
    ///   - associatedData: Optional associated data (RFC 9106 `X`). Empty by default.
    ///   - params: Cost and output parameters.
    public static func deriveKey(
        password: Data,
        salt: Data,
        secret: Data = Data(),
        associatedData: Data = Data(),
        params: Argon2Params
    ) throws -> Data {
        try params.validate()
        let tag = Argon2Engine.derive(
            password: Array(password),
            salt: Array(salt),
            secret: Array(secret),
            ad: Array(associatedData),
            time: params.timeCost,
            memory: params.memoryCostKilobytes,
            threads: params.parallelism,
            keyLen: UInt32(params.outputLength),
            mode: Int(params.variant.rawValue)
        )
        return Data(tag)
    }

    /// Derives a key and compares it against `expected` in constant time.
    ///
    /// Returns `true` only when the freshly derived key is byte-for-byte equal
    /// to `expected`.
    public static func verify(
        password: Data,
        expected: Data,
        salt: Data,
        secret: Data = Data(),
        associatedData: Data = Data(),
        params: Argon2Params
    ) throws -> Bool {
        let actual = try deriveKey(
            password: password, salt: salt, secret: secret,
            associatedData: associatedData, params: params
        )
        return constantTimeEqual(actual, expected)
    }

    /// Returns `length` cryptographically random bytes from the system CSPRNG.
    public static func randomSalt(length: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    /// Constant-time byte comparison over `Data`.
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[a.startIndex + i] ^ b[b.startIndex + i]
        }
        return diff == 0
    }
}