# ClipGum local P2P security architecture

## Scope and trust model

Phase 7 handoff is an explicit, one-shot operation between two ClipGum instances.
It is not a clipboard-history synchronizer and has no account, rendezvous,
cloud relay, centralized signaling service, third-party sync protocol, or
external inference path. `LocalP2PService` is started only while a user-created
handoff window is active.

The transport uses Network.framework `NWBrowser`/`NWListener` with the
`_clipgum._tcp` Bonjour service and `NWConnection`. `includePeerToPeer` permits
supported direct Wi-Fi/AWDL links in addition to the local subnet. A Bonjour
name is discovery metadata only; it is never proof of identity. No IP address,
device name, packet body, or payload is written to diagnostics.

## Pairing and channel establishment

1. Each connection creates a fresh CryptoKit Curve25519/X25519 private key and a
   random 128-bit nonce. The hello contains only protocol version, session ID,
   ephemeral public key, nonce, and a bounded display name.
2. The two hello transcripts are ordered by initiator/responder role and hashed
   with SHA-256. A six-digit short authentication string (SAS) is derived from
   that digest and shown on both devices. Users compare it out of band and must
   explicitly confirm on both devices. A changed key/nonce produces a different
   code; a confirmation with a different transcript is rejected.
3. Only after mutual confirmation does ClipGum derive the shared X25519 secret.
   HKDF-SHA256 uses the transcript as salt and separates initiator-to-responder
   and responder-to-initiator keys.
4. A ready message must then be encrypted and received in both directions before
   a payload is accepted. This prevents a one-sided confirmation from releasing
   data.

This is a ClipGum-specific SAS-authenticated handshake using the requested
X25519 and ChaCha20-Poly1305 primitives; it is not represented as a completed
Noise Protocol Framework implementation or as a formal third-party security
proof. A QR display can be added as a presentation of the same SAS/transcript,
but the current UI uses the numerical code.

## AEAD, framing, and replay rules

- ChaCha20-Poly1305 uses direction-separated keys, a session/direction/sequence
  nonce, and associated data containing session ID, direction, and sequence.
- TCP frames use a four-byte big-endian length, a one-byte kind, and a bounded
  body. The decoder requires exact packet consumption and rejects unknown kinds,
  trailing bytes, invalid UTF-8, oversized lengths, and invalid state transitions.
- Secure envelopes carry a session ID and monotonically increasing sequence.
  Unexpected, replayed, reordered, cross-session, or unauthenticated envelopes
  fail closed. Sequence counters never wrap.
- Payloads are limited to 2 MiB before framing. A transfer has a random UUID and
  must receive an encrypted acknowledgement. Unknown acknowledgements are
  rejected.
- Pairing/handshake has a one-shot 30-second timeout; an established connection
  has a 60-second activity deadline. There is no retry loop. Wi-Fi/path failure
  or timeout cancels the connection and returns discovery to the still-open
  handoff window. Pending text is cleared, so a later transfer requires a new
  explicit send action.

## Sanitization and lifetime

`P2PSession.sendSanitized` runs the deterministic URL/secret cleaner at the
network boundary even if the caller already supplied a preview. The receiver
cleans again before emitting text. Thus a remote “sanitized” label is not a
trust decision. Only plain UTF-8 text is supported; rich pasteboard flavors and
history records are never serialized.

The transport has no history queue. Incremental receive storage and temporary
packet values are wiped on a best-effort basis when consumed or closed. A sender
keeps only the pending transfer identifier in the session and the explicit UI
controller keeps the pending text until encrypted delivery acknowledgement,
cancellation, or close. A receiver holds text only in its visible review
preview; copying it requires a separate explicit action. Swift/Foundation and
Network.framework copies cannot be promised as a general secure-erasure
mechanism, so ClipGum does not claim physical memory forensics resistance.

## Backup relationship

`.clipgum` backups are independent of P2P. They contain an allow-listed typed
configuration payload, never clipboard text, pasteboard flavors, Share-Ready
mappings, device private keys, or session keys. Argon2id/AES-GCM backup details
are in `PLUGINS.md` and the `LocalBackupArchive` implementation.

## Validation boundaries

Automated tests exercise in-memory pairing, malformed packets, authentication
failures, replay/close behavior, sanitized delivery, and backup tamper handling.
They do not prove radio range, AWDL routing, iOS permission prompts, physical
multi-device delivery, or a formal cryptographic audit. Those require the
checklist in `MOBILE.md` and a signed two-device test run.
