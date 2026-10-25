# Fresh macOS profile install and permission-recovery protocol

Perform this manually on a macOS 14+ Apple Silicon test machine using the exact final notarized DMG. A new macOS user account provides a clean TCC/preference/container context; a clean VM snapshot is even better. Do not run this protocol against a developer's daily account.

## Record the environment

- ClipGum display version and `CFBundleVersion`.
- DMG SHA-256 from `clipgum.rb`.
- macOS version/build and Apple Silicon model/unified RAM.
- Whether the install is from DMG or the generated local Cask.
- Date, tester, and actual result for every step. “Not run” is a valid result; “passed” requires observation.

## Clean install

1. Create/sign into a new standard macOS user. Do not copy ClipGum preferences, containers, Keychain entries, or TCC databases from another user.
2. Verify `shasum -a 256 ClipGum-<version>.dmg` matches `clipgum.rb`.
3. Attach the DMG and confirm the window contains `ClipGum.app` and an Applications shortcut.
4. Drag ClipGum to Applications. Optionally repeat through `brew install --cask /path/to/clipgum.rb` in a separate clean profile.
5. Launch from Applications. Record Gatekeeper/notarization behavior; a warning, quarantine prompt, or inability to open is a failure requiring investigation, not something to bypass with Control-click.
6. Confirm the three-step first-run walkthrough appears, diagnostics and automatic update checks are off, and no clipboard read occurs before ⌘⇧V or the menu-bar Smart Paste action.
7. Finish onboarding without selecting a model. Mechanical actions must remain available.

## Permission denial and recovery

1. Copy a nonsensitive test sentence in TextEdit. Invoke ⌘⇧V and verify Before/After preview.
2. Choose **Paste Cleaned** with Accessibility not granted. Confirm the permission request/guidance appears and the existing pasteboard remains unchanged if access is denied.
3. Deny access. Invoke again and choose **Copy Result**; this must work without Accessibility or a synthetic keystroke.
4. Open System Settings → Privacy & Security → Accessibility using ClipGum's button. Enable ClipGum, return, choose **Check Again**, then retry Paste Cleaned. Confirm exactly one ⌘V in the prior app.
5. Disable Accessibility again and repeat step 3 to verify recovery does not require reinstalling.
6. If macOS denies Paste from Other Apps, verify the palette reports denial without content and opens the correct privacy settings. Allow access and invoke again. Do not treat a global shortcut alone as permission to bypass the system prompt.
7. Confirm Input Monitoring is not requested merely by launching, registering the hotkey, or copying. Use its onboarding settings button only if macOS specifically requires that permission for the tested configuration.

## Offline/local-only cycle

1. Load only nonsensitive fixtures. Disable networking at the test-profile or network-emulation level.
2. Exercise copy → ⌘⇧V → deterministic URL Clean, Rich Text Sanitizer, Table Convert, and Bash Inspect → Copy Result/Paste Cleaned. All must work offline and no update/model request should occur.
3. Explicitly opt into a local model and repeat one local transformation while offline. Record the exact model hash and hardware separately; CI mocks are not evidence of model quality.
4. Re-enable networking. Confirm no queued clipboard/diagnostic payload is transmitted.

## Update-channel and tamper checks

1. With automatic checks off, launch and confirm no appcast request occurs until **Check for Updates** (unless the user had explicitly enabled automatic checks in a prior run).
2. Verify stable does not offer a beta-tagged item; beta may offer default and beta items.
3. Test a signed test feed in an isolated release environment. Confirm invalid Ed25519 metadata, unsigned appcast, HTTP enclosure, altered archive bytes, and wrong-signature archives are rejected before installation.
4. Confirm release notes render without JavaScript and no system-profile/feed parameters are sent.
5. Run `./Build/test_sparkle_tamper.sh` for archive-level automated coverage. Separately record the full UI installation test result; do not conflate the two.

## Clear All Data

1. Opt into diagnostics, perform several actions, and inspect Privacy & Audit's exact JSON.
2. Create volatile Share-Ready and Chain Copy state.
3. Choose **Clear All Data** once. Confirm diagnostics are disabled and all counters/latencies/errors/peak RAM reset; volatile preview, chain, and Share-Ready mappings are cleared.
4. Confirm downloaded model files and ordinary inference/update preferences remain, as documented.
5. Quit and relaunch. Diagnostic values must not reappear; only the explicit preferences described in the UI should persist.
