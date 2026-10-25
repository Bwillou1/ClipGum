# Phase 5 distribution and update pipeline

These scripts build an Apple Silicon macOS 14+ app with hardened runtime, a minimal sandbox, Developer ID signing, notarization, a drag-and-drop DMG, a Homebrew Cask, a CycloneDX SBOM, and a signed Sparkle appcast.

## Credential boundary

Never commit signing identities' private keys, Apple credentials, app-specific passwords, notarization credentials, Sparkle private keys, production appcast configuration with embedded credentials, model URLs with credentials, or exported key files.

- Store Apple notarization credentials in a login Keychain profile with `xcrun notarytool store-credentials`; use that profile's name through `NOTARYTOOL_PROFILE`.
- Generate Sparkle's Ed25519 keypair using Sparkle 2.10.0's `generate_keys` tool. Keep the private key in Keychain and use a dedicated account such as `ClipGumRelease` through `SPARKLE_KEYCHAIN_ACCOUNT`. Only `SUPublicEDKey` belongs in the built app's public plist.
- `SIGNING_IDENTITY` is a Developer ID Application identity name visible to `codesign`. The release script rejects ad-hoc signing.
- `SPARKLE_ED_KEY_FILE` exists for controlled signing infrastructure and test fixtures, but a Keychain account is preferred. Do not pass a private key as a command-line argument.

CI uses ad-hoc signatures only to verify bundle structure. It does **not** notarize, staple, or prove Gatekeeper acceptance.

## Development package

```bash
swift package resolve
./Scripts/package_app.sh
./Build/validate_distribution.sh build/ClipGum.app --development
```

Blank `SUFeedURL` and `SUPublicEDKey` values are intentional in source. `UpdateManager` rejects them and does not start Sparkle. Packaging can inject both public values into the **built copy** without modifying `Resources/Info.plist`:

```bash
CLIPGUM_APPCAST_URL=https://updates.example.com/clipgum.xml \
CLIPGUM_SPARKLE_PUBLIC_ED_KEY='32-byte-public-key-in-base64' \
./Scripts/package_app.sh
```

`REQUIRE_UPDATE_CONFIGURATION=1` makes missing production metadata a packaging error.

## Signed/notarized release

Run on a trusted macOS release machine after resolving dependencies and reviewing `Package.resolved`:

```bash
VERSION=0.1.0 \
BUILD_NUMBER=1 \
SIGNING_IDENTITY='Developer ID Application: Your Organization (TEAMID)' \
NOTARYTOOL_PROFILE='ClipGumNotary' \
SPARKLE_KEYCHAIN_ACCOUNT='ClipGumRelease' \
CLIPGUM_APPCAST_URL='https://updates.example.com/clipgum.xml' \
CLIPGUM_SPARKLE_PUBLIC_ED_KEY='32-byte-public-key-in-base64' \
CLIPGUM_DMG_DOWNLOAD_URL='https://updates.example.com/ClipGum-0.1.0.dmg' \
RELEASE_CHANNEL=stable \
RELEASE_NOTES_FILE=/absolute/path/to/public-release-notes.txt \
./Build/release.sh
```

Outputs are written to `build/distribution/`:

- `ClipGum.app` — hardened, sandboxed, Developer ID signed, nested code signed inside-out.
- `ClipGum-<version>.dmg` — UDZO DMG with `ClipGum.app` and `/Applications` symlink, signed, submitted with `notarytool --wait`, stapled, validated, and assessed with `spctl`.
- `clipgum.rb` — Homebrew Cask with the final stapled DMG's automatic SHA-256.
- `SBOM.json` — CycloneDX 1.5 inventory generated from resolved pins.
- `appcast.xml` — enclosure signed with EdDSA and the entire feed signed as required by `SURequireSignedFeed`.

Upload the exact final DMG before publishing the appcast. Publish stable items without a `<sparkle:channel>` element. `RELEASE_CHANNEL=beta` adds `<sparkle:channel>beta</sparkle:channel>`. The generator creates a one-item feed; when maintaining release history, merge prior public items into the feed and then re-sign and re-verify the entire appcast with Sparkle's tool.

Sparkle installs only after user confirmation. Automatic update checks are off by default; automatic downloading/installation is disabled. Stable selects only the default channel; beta adds the named `beta` channel.

## Entitlements and Sparkle process model

The main app has exactly:

- App Sandbox.
- User-selected read-only files for existing local models/manifests.
- Network client for explicit Sparkle checks and explicit verified model downloads.
- Two temporary Mach lookups for Sparkle's InstallerLauncher (`com.clipgum.ClipGum-spks` and `-spki`).

There are no camera, microphone, location, JIT, unsigned-executable-memory, or library-validation entitlements. User-selected read/write access is limited to explicit model selection and rule-pack/encrypted-backup export through system panels; no broad file-system access is granted. The network-server entitlement is used only by the explicitly started Phase 7 Bonjour listener; it does not start at launch. Sparkle's downloader XPC is disabled because Sparkle explicitly warns against combining it with main-app network client. Updates and model downloads run in the main app's isolated network boundary; clipboard/inference/paste services have no URL-loading call sites. Nested Sparkle helper/XPC entitlements are preserved during signing rather than replaced with the main app's network entitlement.

## Model acquisition manifests

`Models/manifest.schema.json` documents the version-1 JSON format. A local manifest declares:

- A safe versioned identifier, display name, `mlx` or `gguf` backend, and minimum unified RAM.
- One to 64 safe filenames, each with an exact HTTPS URL, expected byte count, and SHA-256.
- A GGUF manifest has exactly one `.gguf`; MLX requires `config.json` and at least one `.safetensors` file.
- Total declared size is capped at 8 GiB.

The user selects the manifest and then separately chooses **Download & Verify**. Downloads use an ephemeral, cookieless, credentialless session, cancel on oversize/non-HTTPS redirects, stage inside ClipGum's Application Support container, stream SHA-256 verification, and move into place atomically. Failed/tampered downloads are deleted and existing destinations are not overwritten. A matching hash verifies bytes against the manifest, not publisher identity or model quality. No default model publisher, URL, or hash is hard-coded.

## SBOM and tamper integration

```bash
python3 Build/generate_sbom.py --sync-resource
./Build/test_sparkle_tamper.sh
```

The tamper script uses Sparkle 2.10.0's actual `sign_update --verify` and a deterministic **test-only** key. It verifies an intact archive and requires a modified archive to be rejected. This is archive-signature integration coverage, not a claim that a full replacement-app installation was exercised.

## Required manual release validation

Automated scripts cannot create a fresh macOS user or prove Apple/notary outcomes without real credentials and execution. Follow [`FRESH_PROFILE.md`](FRESH_PROFILE.md) and [`VALIDATION.md`](VALIDATION.md) on the signed/notarized artifact. Record actual results in the release checklist; do not substitute CI packaging success for these checks.
