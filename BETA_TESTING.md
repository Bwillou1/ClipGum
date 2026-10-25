# ClipGum Public Beta Testing Guide

Thank you for testing ClipGum on macOS 14+ Apple Silicon. The beta's central promise is explicit, local transformation: copy normally, invoke **⌘⇧V**, inspect the preview, and only then choose Copy or Paste.

## Before you start

- Use nonsensitive fixtures until you have verified the workflow on your Mac.
- Install only a release whose DMG SHA-256 and source/version you trust. Follow the release's notarization/Gatekeeper notes; do not bypass macOS warnings to make a test pass.
- Review [`Build/FRESH_PROFILE.md`](Build/FRESH_PROFILE.md) for a clean-user install and permission-recovery protocol.
- Mechanical actions need no model. For local inference, use a model and license you trust, sufficient unified RAM, and exact weight hashes. No PrismML or other model weights are bundled.
- A verified model manifest proves that downloaded bytes match its declared SHA-256. It does not prove publisher identity, model quality, safety, or license suitability.

## Privacy guarantees and boundaries

### Clipboard and inference

- The general pasteboard is read only after explicit ⌘⇧V/menu invocation. There is no polling, watcher, history, automatic rewrite, or app-profile-triggered read.
- Concealed, transient, auto-generated, and recognized password-manager markers are checked before content-flavor reads. Marker coverage depends on the source app and is not a universal secret detector.
- Mechanical actions do not invoke inference. LLM actions use only deterministically cleaned input and an explicitly selected local model.
- Clipboard text, transformed output, regex tokens, and Share-Ready/session mappings are not accepted by ClipGum's diagnostics API and are never intentionally sent to app logs, app crash reporting, diagnostics payloads, or network requests.
- ClipGum registers no analytics SDK, telemetry endpoint, or crash reporter. macOS may produce its own crash reports according to your system privacy settings; those operating-system reports are outside ClipGum's telemetry implementation and are not claimed to be controllable by the app.

### Network

Copy/transform/paste and local inference contain no network call path. Only these features can use ClipGum's network-client entitlement:

1. An explicit Sparkle update check, or a scheduled check after you explicitly enable automatic checks.
2. An explicit model download after selecting and reviewing a verified manifest.

Updates require strict HTTPS, a valid Ed25519 public key, a signed appcast, and pre-extraction archive verification. Sparkle system-profile fields and additional feed parameters are disabled. Automatic downloads/installation are disabled; installation still requires confirmation. Your network provider and the update/model host can observe ordinary connection metadata such as IP address and requested URL, but ClipGum does not include clipboard content in those requests.

### Diagnostics and Clear All Data

Diagnostics are **off by default** and require opt-in during onboarding or in Settings → Privacy & Audit. When enabled, ClipGum keeps only volatile, non-content values:

- Closed-vocabulary feature activation counts such as `cleaned_link` and `table_to_csv`.
- Nearest-rank p50/p95 execution latency in milliseconds.
- Peak whole-process resident RAM.
- Closed-vocabulary error codes such as `model_out_of_memory`.

There is no automatic transmission. The inspector displays the exact canonical JSON before you choose **Copy Exact JSON**, which is itself an explicit pasteboard write. **Clear All Data** clears diagnostic values and withdraws opt-in; the same action clears volatile preview, Chain Copy, and Share-Ready mappings. It does not delete downloaded model files or ordinary preferences.

## How to provide useful feedback

Use [GitHub Issues](https://github.com/Bwillou1/ClipGum/issues) for reproducible beta feedback. Include:

- ClipGum version/build, macOS version, Mac model, and unified RAM.
- DMG or Cask installation method and the artifact SHA-256 when relevant.
- Exact minimal steps, expected result, actual result, and whether the issue reproduces in a fresh macOS user.
- The action/category (for example URL Clean or Table Convert), **not** the private source text.
- Optionally, the exact non-content JSON copied from Privacy & Audit after reviewing every field.

Never attach real clipboard contents, secrets, private model weights, proprietary documents, Share-Ready mappings, personal URLs, or confidential screenshots. Create a synthetic minimal fixture instead. For a suspected security vulnerability, use the repository's private vulnerability-reporting mechanism if available rather than publishing sensitive details in an issue.

## Core test protocols

### 1. Explicit-only and sensitive-marker behavior

1. Copy a synthetic sentence; do not invoke ClipGum. Confirm no palette/history/write occurs.
2. Invoke ⌘⇧V once and verify one Before/After capture.
3. Cancel/Escape/outside-click and confirm the pasteboard did not change.
4. Test concealed/transient/password-manager copies with a source that emits those markers. Confirm ClipGum reports a metadata skip and never displays the value.

### 2. Zero-outbound transformation cycle

1. Disconnect networking or use a per-app network test harness.
2. Exercise URL Clean, Regex Secret Scrub, JSON Pretty, Table Convert, Rich Text Sanitizer, PDF Repair, and Bash Inspect through copy → preview → Copy/Paste.
3. Confirm correct output and zero requests. Repeat one explicitly selected local-model action while offline.
4. Review the automated `NetworkIsolationTests` scope; a source audit and URL-protocol recorder complement, but do not replace, external network observation.

### 3. Permission recovery

Follow [`Build/FRESH_PROFILE.md`](Build/FRESH_PROFILE.md). Verify Accessibility denial leaves the pasteboard untouched, Copy Result still works, and granting/checking again restores one explicit ⌘V. Verify Input Monitoring is not requested unnecessarily.

### 4. Model integrity and memory

1. Select a local manifest and review every URL/hash before Download & Verify.
2. Test a fixture with one altered byte and one with a wrong declared length; both must be deleted without a final model directory.
3. Test insufficient declared RAM and an already-installed identifier; neither should start a download or overwrite files.
4. For a real model, record publisher revision, SHA-256, quantization, load/generation/unload RAM, latency, and manual semantic failures. CI's mocks do not establish model quality or memory release on your hardware.

### 5. Updates and tampering

1. Confirm automatic checks are initially off. Test manual Check for Updates, release notes, and daily/weekly settings only after explicit opt-in.
2. Confirm stable ignores beta-only items and beta accepts the explicit beta channel.
3. In an isolated test-feed environment, verify unsigned appcasts, non-HTTPS enclosures, wrong keys/signatures, and altered archives fail before installation.
4. Run `./Build/test_sparkle_tamper.sh` for Sparkle archive-signature integration coverage. Record full update installation separately.

### 6. Office and deterministic regressions

- Compare protected numbers, currencies, named/numeric dates, and formulas before/after every Office model action. A data-discrepancy badge must block export.
- Test HTML tables, quoted/multiline CSV, semicolon decimal commas, and rich-text lists/links/tables. Confirm one pasteboard item with consistent plain/HTML/RTF output.
- Confirm Bash Inspect never executes its input; absence of a finding is not a safety proof.

## Known validation limits

The repository's CI can compile, run mocked/unit/integration tests, package, and inspect ad-hoc signatures. It cannot by itself prove real notarization, Gatekeeper acceptance, a fresh-user install, physical Apple Silicon model behavior, or a complete Sparkle update. Consult each release's actual validation record and report “not run” rather than inferring a pass.
