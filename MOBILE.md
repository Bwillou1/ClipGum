# ClipGum mobile companion and multi-device checklist

## Build and install

The mobile target specification is `Targets/ClipGumMobile/project.yml`. Install
XcodeGen, generate `ClipGumMobile.xcodeproj` from that directory, and open it in
a current Xcode release with an iOS 17+ SDK. Select a development team and sign
an app/extension bundle set for a physical device. The repository does not
include signing identities, provisioning profiles, model weights, or a claim of
an installed build.

The app, Action Extension, and Keyboard Extension link the root package's
`ClipGumCore` product. The macOS AppKit/MLX product is not a mobile dependency.
Deterministic regex rules remain available in core. The iOS profile refuses
custom JavaScript evaluation instead of resolving macOS's private watchdog
symbols; this does not affect the built-in deterministic cleaning actions.

## Share Sheet Action Extension

1. Enable the ClipGum action from the iOS/iPadOS Share Sheet.
2. Share a plain-text selection from Safari, Notes, or another provider.
3. Review the supplied text in the extension, choose Clean, Scrub secrets, or
   Strip tracking URLs, then choose **Return cleaned text**.
4. The extension returns a new `NSExtensionItem`; it does not read or write the
   general pasteboard and does not retain a history. Shared text is capped at
   2 MiB before any cleaning action is performed.

Web-page activation is limited to one item. Providers that supply only a URL or
binary attachment may offer no plain-text item; ClipGum then reports that no
supported text was supplied rather than fetching the URL.

## Optional keyboard

1. Enable the keyboard in iOS Settings and review the system's full-access/paste
   permission explanation. The keyboard is optional and is not required for
   Share Sheet cleaning.
2. In a text field, tap **Paste Clean**. Only this button callback reads
   `UIPasteboard.general.string`, cleans it locally, and inserts the result via
   `textDocumentProxy`.
3. There is no pasteboard observer, launch read, timer, history, or automatic
   insertion. If iOS denies paste access, no fallback read is attempted.

## Local handoff

1. On the Mac, invoke ClipGum explicitly, review a cleaned result, and choose
   **Send Sanitized to Device**. On mobile, open **Local Handoff / Receive**
   directly, or **Send to device** from a cleaned preview, then choose the
   desired manual action.
2. Start local discovery only in that window. Grant Local Network permission if
   requested. Both ends must be on the same local network or a supported direct
   AWDL path.
3. Select the other instance, compare the six-digit code on both screens, and
   confirm on both. Do not accept a code that differs or appears unexpectedly.
4. Wait for the authenticated ready state and delivery acknowledgement. The
   receiver reviews sanitized text and separately chooses Copy if desired.
5. Close the handoff window to stop browsing/listening. Leaving Wi-Fi range,
   denying permission, or a timeout terminates the session; it does not queue a
   later automatic transfer.

## CoreML and thermal behavior

A user may select a compiled local `.mlmodelc` file. The adapter uses CoreML
with CPU/Neural Engine compute units, bounded input/output, and a 500 MiB total
model-artifact budget (including files inside a compiled model package). The
selected security scope is retained for the model's lifetime. That file gate is
not a measurement of arbitrary model runtime
memory. Model input is deterministically cleaned before inference and output is
cleaned again. Serious/critical thermal pressure or an unsupported model output
selects the same deterministic cleaner as a fallback. The constrained adapter
expects string features named `text` and `output`; other schemas fail to that
fallback rather than invoking another provider. No weights or prompts are
downloaded.

## Manual validation matrix

- [ ] Fresh iOS/iPadOS profile: install, permission denial, permission recovery,
      and extension removal/reinstallation.
- [ ] Share Sheet with Safari text, Notes text, empty text, non-text attachment,
      and a very large bounded item.
- [ ] Keyboard paste permission denied/allowed; verify no read before a tap.
- [ ] Two-device pairing with matching and intentionally different SAS codes.
- [ ] Airplane mode/no network: deterministic cleaning still works; P2P fails
      closed without contacting a relay.
- [ ] Local Wi-Fi and supported AWDL paths; disable Wi-Fi mid-transfer and verify
      termination, no retry queue, and no automatic clipboard write.
- [ ] Malformed/untrusted packet injection: reject before payload delivery.
- [ ] Backup export/import with wrong password, modified ciphertext, excessive
      KDF parameters, and a configuration audit showing no clipboard history.
- [ ] Physical cold-start and 72-hour idle/thermal measurements using the
      performance harness; record hardware, OS, and build identifiers.

Automated repository tests cover protocol and deterministic boundaries only;
unchecked physical-device items are not claimed as completed.
