# Vendored Argon2 provenance

- Upstream: https://github.com/colt3k/argon2-swift
- Exact source revision: `bcf667c8ee59ad6014bdac1474b5e717a0b95844` (`v0.1.0`)
- License: MIT; the unmodified upstream `LICENSE` is included beside this file.
- Vendored files: `Argon2.swift`, `Argon2Engine.swift`, `Argon2Error.swift`,
  `Argon2Params.swift`, `Blake2b.swift`, `ByteHelpers.swift`, and `Wipe.swift`.
  Unused upstream vault/PHC helpers are intentionally not included.

## Local compatibility patch

`ByteHelpers.swift` splits `leUint64` into `low` and `high` subexpressions.
The unmodified upstream expression exceeds the Swift 6 compiler's default
type-checker budget on the GitHub macOS runner. The same eight bytes, shifts,
and bitwise OR operations are retained; this is not an algorithm or parameter
change.

The source is vendored so this required compatibility fix applies to ordinary
consumer and CI builds without a mutable dependency branch, global compiler
flags, or a post-checkout mutation. RFC 9106 known-answer coverage is included
in ClipGum's Phase 7 tests. Review and re-pin deliberately when updating.
