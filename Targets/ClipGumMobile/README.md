# ClipGum mobile companion

`project.yml` describes an iOS/iPadOS 17+ application, a Share Sheet Action
Extension, and an optional Custom Keyboard Extension. Generate the project with
XcodeGen from this directory:

```sh
xcodegen generate --spec project.yml
```

The three targets link the root package's `ClipGumCore` product. The macOS
MLX/AppKit executable is not linked into mobile targets.

## Privacy boundaries

- The app screen accepts text entered or supplied by an explicit Share Sheet
  action. It does not read the general pasteboard on launch or in the background.
- The Action Extension consumes only `NSExtensionItem` plain-text attachments
  and returns a cleaned `NSExtensionItem`.
- The keyboard has no observer or timer. Its sole `UIPasteboard` read is in the
  `Paste Clean` button callback; iOS still controls any paste permission/full
  access requirement.
- CoreML models are selected locally by the user. No model URL, weight, prompt,
  or output is sent to a server. The 500 MiB file-size gate is a resource budget,
  not a claim of measured runtime memory for an arbitrary third-party model.
- Local handoff starts only from the handoff button. It uses the shared Bonjour /
  AWDL + SAS/X25519/ChaCha20-Poly1305 implementation and does not synchronize a
  history.

The project has not been signed, installed, or exercised on a physical iOS or
iPadOS device in this repository's Linux/macOS CI environment. See
`../../MOBILE.md` for the manual validation checklist.
