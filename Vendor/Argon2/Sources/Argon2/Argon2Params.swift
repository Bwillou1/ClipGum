/// The three Argon2 variants defined by RFC 9106.
public enum Argon2Variant: UInt32, Equatable, Sendable, CaseIterable {
    case d = 0
    case i = 1
    case id = 2
}

/// The cost and output parameters for an Argon2 derivation.
///
/// `memoryCostKilobytes` is expressed in kibibytes (KiB), matching the
/// `m` parameter of RFC 9106. `outputLength` is the tag length in bytes.
public struct Argon2Params: Equatable, Sendable {
    public var variant: Argon2Variant
    public var timeCost: UInt32
    public var memoryCostKilobytes: UInt32
    public var parallelism: UInt32
    public var outputLength: Int
    public var version: UInt32

    public init(
        variant: Argon2Variant = .id,
        timeCost: UInt32,
        memoryCostKilobytes: UInt32,
        parallelism: UInt32,
        outputLength: Int = 32,
        version: UInt32 = 0x13
    ) {
        self.variant = variant
        self.timeCost = timeCost
        self.memoryCostKilobytes = memoryCostKilobytes
        self.parallelism = parallelism
        self.outputLength = outputLength
        self.version = version
    }

    /// Validates the parameters against the RFC 9106 Section 3.1 constraints.
    ///
    /// - version must be `0x13` (the only version this library supports)
    /// - `timeCost` >= 1
    /// - `parallelism` >= 1
    /// - `outputLength` >= 4 bytes
    /// - `memoryCostKilobytes` >= 8 * `parallelism`
    public func validate() throws {
        if version != 0x13 {
            throw Argon2Error.invalidParameters("only version 0x13 (v1.3) is supported")
        }
        if timeCost < 1 {
            throw Argon2Error.invalidParameters("timeCost must be >= 1")
        }
        if parallelism < 1 {
            throw Argon2Error.invalidParameters("parallelism must be >= 1")
        }
        if outputLength < 4 {
            throw Argon2Error.invalidParameters("outputLength must be >= 4 bytes")
        }
        if memoryCostKilobytes < 8 * parallelism {
            throw Argon2Error.invalidParameters(
                "memoryCostKilobytes must be >= 8 * parallelism (\(8 * parallelism))")
        }
    }
}