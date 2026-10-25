/// Errors surfaced by the public `Argon2` and `PasswordVault` APIs.
public enum Argon2Error: Error, Equatable {
    /// The supplied parameters violate the RFC 9106 constraints (Section 3.1).
    case invalidParameters(String)
    /// The supplied salt has an unsupported length.
    case invalidSaltLength(Int)
    /// The supplied key length is out of range.
    case invalidKeyLength(Int)
    /// A PHC-format string could not be parsed.
    case malformedPHC(String)
    /// The ciphertext failed authentication when decrypted.
    case authenticationFailed
    /// The ciphertext is too short to be a valid vault record.
    case malformedCiphertext
    /// The stored record was not produced by `PasswordVault` (wrong variant /
    /// key length), so it cannot be opened with this vault.
    case incompatibleRecord(String)
}