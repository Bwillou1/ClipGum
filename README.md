# ClipGum

**Phase 2 — Smart Paste & Local Inference for macOS 14+ on Apple Silicon.**

Copy normally, press **⌘⇧V**, inspect deterministic or locally generated output, then choose exactly what happens next. ClipGum still does not watch clipboard changes, keep history, perform cloud inference, or rewrite the pasteboard on its own.

- **Platform:** Swift / SwiftUI / AppKit, macOS 14+
- **Inference:** optional local MLX or GGUF on Apple Silicon; never required for mechanical actions
- **Build:** Swift Package Manager with pinned direct dependencies
- **UI:** one `NSStatusItem`, one Carbon global hotkey, one floating `NSPanel`
- **License:** Apache-2.0 (see [`LICENSE`](LICENSE))

## Explicit workflow

1. Copy one plain-text item in any app.
2. Press **⌘⇧V**, or choose **Smart Paste…** from ClipGum's menu bar item.
3. ClipGum checks pasteboard access and sensitive-type metadata, then reads the text once.
4. `RuleCleaningService` immediately produces a deterministic Before/After preview. No model is loaded by this step.
5. Optionally select an action and choose **Run**:
   - Mechanical actions execute synchronously without calling an inference engine.
   - LLM actions require an explicitly selected local model and stream provisional output.
6. Review the exact diff and validation messages, then choose:
   - **Paste Cleaned** — writes approved output and sends ⌘V to the previous app.
   - **Copy Result** — writes only approved output; paste it yourself.
   - **Paste Original** — writes the captured original plain text and sends ⌘V.
   - **Cancel**, **Escape**, or an outside click — closes without a pasteboard write.

Pressing ⌘⇧V while the palette is open dismisses it without another clipboard read. Copy/Paste Cleaned is disabled during streaming and after any error-severity validation failure.

### Deliberate non-goals

There is no clipboard history, polling loop, launch-time clipboard read, rich-text preservation, multi-item merging, automatic pasteboard restoration, telemetry, cloud inference, automatic model download, or autonomous agent/tool execution. “Paste Original” means the original **plain-text representation**, not every original RTF/HTML representation.

## Two-stage execution pipeline

### Stage 1: deterministic and engine-free

| Action | Implementation | Calls an engine? |
| --- | --- | --- |
| Clean + Redact | URL de-tracking → regex secret reduction | Never |
| URL Clean | Raw-byte tracker removal only | Never |
| Regex Secret Scrub | Secret rules only | Never |
| JSON Format | `JSONSerialization` validation, sorted keys, pretty printing | Never |

`SmartPastePipeline.mechanicalResult` is synchronous. Its tests use a mock engine and verify that none of these paths calls `transform`.

### Stage 2: explicitly selected local LLM

- **CORRECTION ONLY** — spelling/grammar/punctuation while instructing the model to retain facts, numbers, tone, style, code, and redaction markers.
- **REWRITE** — professional, concise wording with no injected data, facts, numbers, examples, citations, URLs, or code.
- **TABLE TO CSV** — TSV/Markdown-table conversion with stable row/column ordering and RFC 4180-style quoting.

System instructions and untrusted input remain separate arguments through `InferenceEngine`. Clipboard text is not interpolated into the instruction template. Before any LLM call, the full deterministic URL/secret pipeline runs; the engine receives only that cleaned text, not the raw clipboard value.

Streaming chunks are provisional UI state. A final `TransformationResult` is emitted only after output-budget enforcement, transport-wrapper removal, and post-validation.

## Build and runtime prerequisites

### For the app and deterministic tests

- macOS 14.0 or later to run.
- **Xcode 16.3 or newer** to build. The macOS 15.4 SDK is required at compile time for `NSPasteboard.accessBehavior`; deployment remains macOS 14.
- Swift Package Manager resolves:
  - `mlx-swift` **0.25.6**
  - `mlx-swift-lm` **2.25.9**
  - `mattt/llama.swift` at commit `018619bf56f92cc85286150611609f456813826f`, which re-exports llama.cpp **b10549**'s prebuilt XCFramework.

No model weights are bundled. Unit tests use mocks and do not download or load a model.

### Additional requirements for local inference

- An **Apple Silicon** Mac. Backends fail safely with `unsupportedArchitecture` elsewhere.
- A local model already acquired from a publisher you trust:
  - **MLX:** a model directory containing `config.json`, tokenizer files, and one or more `.safetensors` files.
  - **GGUF:** a local `.gguf` file supported by llama.cpp b10549. An instruct model with an embedded chat template is strongly recommended.
- Sufficient unified memory for weights, context, Metal buffers, and the rest of the system. Start with a small 2B/4B quantized instruct model.

ClipGum does not hard-code an unverified Ternary Bonsai repository or claim that a particular PTQ1_0 artifact was evaluated. Compatible local **Ternary Bonsai 2B/4B MLX conversions** or **GGUF PTQ1_0** artifacts use the same loaders. Verify the publisher, model license, SHA-256, conversion metadata, and chat template before evaluation.

### Test and package

```bash
swift test
./Scripts/package_app.sh
open build/ClipGum.app
```

Or build and open in one step:

```bash
./Scripts/package_app.sh --open
```

Tests use unique **named pasteboards**, never `NSPasteboard.general`, so they do not overwrite the developer's real clipboard. The package script builds a release executable, creates `build/ClipGum.app`, installs sandbox metadata, and ad-hoc signs it for local development. It is not a Developer ID/notarization pipeline. Accessibility grants can be tied to a code signature, so macOS may ask again after rebuilding or moving an ad-hoc signed app.

A macOS CI workflow runs tests and packaging on pushes and pull requests.

## Select, evaluate, and unload a model

1. Prepare a local model as described above.
2. From ClipGum's menu, choose **Choose MLX Model Folder…** or **Choose GGUF Model…**.
3. `NSOpenPanel` grants session-only, read-only access. The path is not saved in preferences or a bookmark.
4. Wait for **Ready · Model Loaded · … RAM**. The RAM value is ClipGum's current **whole-process resident footprint**, not a model-only allocation claim.
5. Invoke Smart Paste, select an LLM action, and explicitly choose **Run**.
6. Use **Inference Settings…** to configure temperature (0.1–0.3), output cap (64–512 tokens), and idle timeout. The default is 0.2, 256 tokens, and five minutes.
7. After the idle timeout, the coordinator unloads the model. A later explicit Run can reload it through the still-open session access. **Unload Model** releases the model and that access immediately.

### Resource boundaries

| Boundary | Default / behavior |
| --- | --- |
| Output tokens | 256 default; engine-side clamp to the configured value; absolute maximum 512 |
| Temperature | 0.2 default; clamped to 0.1–0.3 |
| Input | 32 KiB UTF-8 default; actual MLX token count also preflighted |
| Context | 4,096 tokens default; prompt + output must fit |
| Output allocation | Independent UTF-8 byte budget; overflow discards the stream |
| MLX memory | 6 GiB non-relaxed memory limit and 256 MiB cache limit |
| Model files | 8 GiB default maximum across MLX safetensors or one GGUF |
| GGUF decoding | 1,024-token batches, bounded context, cancellation between tokens |
| Idle lifecycle | One-shot `Task.sleep`, then unload only if no generation is active |
| OOM | Typed error, partial output discarded, model unloaded, deterministic preview restored |

MLX drops `ModelContainer` and clears cached Metal buffers. GGUF releases sampler, batch, context, model, and backend in ownership order. Resident RAM can remain with the system allocator briefly; an immediate Activity Monitor drop is not guaranteed.

### Model evaluation checklist

Evaluate each candidate model/quantization on the target Mac before relying on it:

1. **Baseline:** run every mechanical action with no model loaded and confirm identical results and no model status transition.
2. **Correction:** include spelling errors, decimal/version/date numbers, inline code, a fenced code block, Unicode, and `[SECRET_REDACTED]`. Numbers/code must remain exact.
3. **Rewrite:** use source text with concrete claims and numbers. Check professional tone and manually verify that no new claim was introduced; lexical validation is only a heuristic.
4. **CSV:** use TSV and Markdown tables with empty cells, commas, quotes, Unicode, and multiline quoted CSV fields. Every output cell must equal the source matrix.
5. **Prompt injection:** put “ignore previous instructions” and fake assistant/system markers inside the data. They must be treated as content, not commands.
6. **Streaming:** confirm chunks appear incrementally and Copy/Paste Cleaned stays disabled until completion.
7. **Validation:** confirm altered numbers/code/secrets, malformed CSV, and highly divergent output are blocked. Test **Use Deterministic** and **Paste Original**.
8. **Cancellation:** cancel mid-stream and verify no pasteboard write, then confirm eventual idle unload.
9. **Memory:** record resident footprint before load, at Ready, during generation, and after unload. Repeat with the one-minute idle setting.
10. **Failure handling:** use the mock-driven OOM tests for repeatable failure verification; additionally check that an incompatible/oversized local model fails without exposing partial output.
11. **Quality record:** document model identifier, publisher revision/hash, quantization, temperature, token cap, elapsed time, validation failures, and manual semantic errors. Do not compare models using only token speed.

## Post-validation and output safety

`OutputSanitizer` removes only known outer fences and labels such as `Output:` or `CSV:`; it does not repair content to force approval.

`OutputValidator` then applies:

- Empty-output and unsupported-control-character rejection.
- Detectable secret/private-IP/internal-host regeneration checks and redaction-marker preservation.
- Exact numeric-token multiset preservation for Correction and Rewrite.
- Exact fenced-code-block and inline-code-span preservation.
- TSV/Markdown source-matrix extraction, CSV syntax/column validation, and exact cell/order comparison for Table to CSV.
- Semantic-overlap/edit-distance heuristics that emit review warnings or block severe divergence.

**Passing validation is not proof of factual or semantic equivalence.** Regex secret detection remains best-effort, and lexical overlap cannot detect every hallucination. The preview remains mandatory. Error-severity issues disable model-output export; **Use Deterministic** restores the Stage 1 result. Engine throws, including OOM, never emit a completed model result and restore that result automatically.

## Streaming UI and exact diff

The floating palette retains one observable session while tokens arrive. It provides:

- Live local-stream/chunk status and provisional-output labeling.
- Side-by-side Before/After and inline diff modes.
- Exact token/whitespace-preserving differences: red strikethrough for removals and green underline for additions.
- The same four explicit safety actions as Phase 1.

The single menu-bar status item reports Idle, Loading, Ready/Model Loaded with resident RAM, Generating, Unloading, and safe failure states. Model content and clipboard text never appear in that status.

## Permissions and privacy boundaries

### Pasteboard access

On macOS 15.4+, `SystemPasteboard` checks [`NSPasteboard.accessBehavior`](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-86972) before any type or value access:

| State | Explicit-trigger behavior |
| --- | --- |
| `.alwaysAllow` | Read once. |
| `.default` / `.ask` | Read once in response to the user's action; macOS may show consent UI. |
| `.alwaysDeny` | Return before type/value access and show a settings path. |
| Unknown future raw value | Fail closed. |
| API unavailable (macOS 14) | Read only inside the same explicit-trigger entry point. |

A global hotkey or menu command is an explicit ClipGum action, but it is not silently treated as a system-wide paste permission grant.

### Concealed and transient content

Before calling `string(forType:)`, ClipGum inspects advertised types and **every item's types**. Any of these markers rejects the entire read:

- `org.nspasteboard.ConcealedType`
- `org.nspasteboard.TransientType`
- `org.nspasteboard.AutoGeneratedType`
- Legacy 1Password, KeeWeb, TypeIt4Me, TextExpander, and Typinator conventions listed in `PasteboardTypePolicy`.

The UI reports only that metadata caused a skip; it does not display the skipped value. These conventions depend on the source app and cannot identify every sensitive copy.

### Accessibility

Accessibility is requested **only for Paste Cleaned / Paste Original**, because those actions synthesize ⌘V with `CGEvent`. It is not needed for the global Carbon hotkey, model inference, or Copy Result. The permission check happens before `clearContents()`, so denial is non-destructive.

### Local model and non-destructive guarantees

- The only production general-pasteboard read is `handleExplicitUserTrigger()` in `AppDelegate`.
- Preview, Cancel, Escape, outside-click dismissal, and excluded content perform no writes.
- Writes exist only in `writeTextForExplicitUserAction`, called by Copy Result or an approved paste action.
- Mechanical actions do not load or call a model.
- Models load only after explicit file selection or an explicit LLM Run.
- No inference network entitlement or app network client is present; MLX uses `.directory`, not a repository downloader.
- The sandbox adds only user-selected read-only file access for local models. There is no persistent bookmark entitlement.
- Preferences contain only temperature/token/idle settings. Clipboard data, prompts, output, and model paths are not persisted.
- Clipboard contents are not logged. ClipGum also installs a no-op llama.cpp logger to avoid third-party stderr prompt/output leakage.
- Dismissal cancels the consumer task and releases the palette's original/generated text and hosting content.

## Deterministic rules

`RuleCleaningService` remains stateless and synchronous: **URL cleaning → secret redaction**. Running it again on cleaned output is idempotent.

### URL de-tracking

HTTP(S) URLs are found in plain text. `URLComponents` validates candidates but never rebuilds them. The cleaner edits only removed raw query fields, preserving surviving parameter order, duplicates, values, percent-escape spelling, path parameters, user info, ports, and fragments.

Removed names, case-insensitively:

- `utm_*`
- `fbclid`, `gclid`, `dclid`
- `gbraid`, `wbraid`, `msclkid`
- `mc_cid`, `mc_eid`, `mkt_tok`

Names are percent-decoded only for comparison. Unknown or potentially functional keys such as `id`, `q`, `ref`, `source`, `token`, and `si` are retained. Malformed percent escapes and candidates rejected by `URLComponents` remain untouched. If all fields are removed, the dangling `?` is removed and the fragment remains.

```text
https://example.com/session;v=2?id=42&utm_source=mail&fbclid=abc#part
→
https://example.com/session;v=2?id=42#part
```

### Secret reduction

Every replacement is exactly `[SECRET_REDACTED]`.

| Rule | Coverage |
| --- | --- |
| AWS access-key shapes | `A3T…`, `AKIA`, `ASIA`, `ABIA`, `ACCA` forms with validated character/length shape. |
| Generic assignments | Values of at least 12 token characters for names such as `api_key`, `apiKey`, `access_token`, `client_secret`, `token`, `password`, and prefixed snake-case variants. |
| Bearer values | `Authorization: Bearer …` and other `Bearer <token>` strings. |
| RFC1918 IPv4 | `10/8`, `172.16/12`, and `192.168/16`; octets are range-checked. |
| Internal hostnames | `.internal`, `.intranet`, `.intra`, `.corp`, `.local`, `.lan`, and `.home.arpa` suffixes. |

This is **best-effort risk reduction, not DLP or guaranteed anonymization**. Unknown token formats, AWS secret keys without an identifying assignment, IPv6, single-label internal hosts, and unmarked secrets can be missed. False positives are possible.

## Architecture

```text
Sources/ClipGum/
├── App/
│   ├── ClipGumApp.swift              # SwiftUI entry and inference settings scene
│   ├── AppDelegate.swift             # Explicit reads, action routing, fallback, model selection
│   └── MenuBarController.swift       # One NSStatusItem and model/RAM status
├── Core/
│   ├── Clipboard/                    # Sole read/write gateway and sensitive markers
│   ├── Hotkeys/GlobalHotKey.swift    # Carbon ⌘⇧V registration and teardown
│   ├── Paste/PasteService.swift      # Explicit copy, Accessibility check, ⌘V posting
│   └── Inference/
│       ├── InferenceEngine.swift     # Required protocol, resource config, safe errors
│       ├── LocalInferenceEngine.swift# Serialization, status, OOM and idle offload
│       ├── MLXInferenceEngine.swift  # Local MLX directory loading/token streaming
│       ├── GGUFInferenceEngine.swift # llama.cpp C API actor wrapper and cleanup
│       ├── ModelIdentifier.swift
│       ├── ProcessMemoryUsage.swift
│       └── SecurityScopedModelAccess.swift
├── Services/
│   ├── Deterministic/                # Phase 1 immutable rules
│   └── Pipeline/
│       ├── SmartPastePipeline.swift  # Mechanical bypass → stream → validation
│       ├── SmartPasteAction.swift
│       ├── PromptTemplate.swift
│       ├── OutputSanitizer.swift
│       ├── OutputValidator.swift
│       ├── CSVDocument.swift
│       ├── TableDataExtractor.swift
│       └── JSONFormattingService.swift
└── UI/
    ├── Diff/InlineDiff.swift         # Exact token/whitespace inline differences
    ├── Palette/                      # Floating streaming preview and four actions
    └── Settings/                     # Resource-only preferences and settings UI

Tests/ClipGumTests/                   # 127 XCTest cases; no model weights required
Resources/                            # Info.plist and minimal sandbox entitlements
Scripts/package_app.sh                # Repeatable local .app packaging
```

Delayed work consists of the one-shot paste focus handoff and one-shot idle offload. Neither polls the pasteboard.

## Tests and manual verification

The **127 XCTest cases** cover:

- All Phase 1 URL, secret, pasteboard-marker, access-policy, and explicit-paste behavior.
- Prompt contents/non-interpolation, configuration clamps, local identifiers, and safe OOM classification.
- Every mechanical engine bypass, cleaned-only model input, token/output bounds, streaming completion, and OOM before/during streaming.
- Numeric/code preservation, secret regeneration, redaction markers, semantic warnings/failures, CSV syntax/schema/cell equality, and output unwrapping.
- Exact diff reconstruction with insertions, removals, replacements, whitespace, punctuation, CRLF, and Unicode.
- Backend selection, idempotent loads, busy-state protection, configuration updates, idle offload, and OOM cleanup/status.

Before a release, manually verify on each supported macOS line and Apple Silicon target:

1. ⌘⇧V works from TextEdit, Safari, Terminal, and an IDE; a conflicting second app leaves the menu action usable.
2. Cancel, Escape, and outside click preserve the exact system pasteboard and release preview text.
3. Real password-manager copies marked concealed/transient never reach the preview.
4. `.ask`, `.alwaysAllow`, and `.alwaysDeny` pasteboard settings behave as documented.
5. Denied Accessibility leaves the pasteboard untouched; Copy Result still works.
6. Paste targets the app that was frontmost when ClipGum was invoked.
7. VoiceOver can reach Before/After text, validation messages, action picker, diff controls, and all four actions.
8. Complete the model evaluation checklist above for each shipping model/quantization.

## Open-source implementation references and credits

References are pinned to inspected revisions. ClipGum's coordinator, validation, UI, and wrappers are original; third-party runtime packages retain their own licenses. No GPL-licensed source from Ice or AltTab is incorporated.

| Mechanism | Studied source | What was adapted — and what was not |
| --- | --- | --- |
| MLX generation and model lifecycle | [MLX Swift LM `Streamlined.swift`](https://github.com/ml-explore/mlx-swift-lm/blob/110f3e1865530df33433610c07ff46264f1bc9b4/Libraries/MLXLMCommon/Streamlined.swift), [MLX Examples `ChatModel.swift`](https://github.com/ml-explore/mlx-swift-examples/blob/378f2449c257788c5067b9f8b086731d76b39b33/Applications/LLMBasic/ChatModel.swift) | `ModelContainer`, `ChatSession`, `GenerateParameters`, and chunk streaming patterns. ClipGum uses only local directories, adds actual-token preflight and strict caps, and does not retain a conversation. |
| MLX unified-memory controls | [MLX Swift `GPU.swift`](https://github.com/ml-explore/mlx-swift/blob/96c0f69cf15f38abd6248bb71fca908171dab1d8/Source/MLX/GPU.swift) | Non-relaxed memory/cache limits, resident-memory qualification, and `clearCache()` after dropping the model container. |
| llama.cpp C API and Swift ownership | [llama.cpp `llama.h`](https://github.com/ggml-org/llama.cpp/blob/b2e5e9b28b2484fbf94b543432ece638996a8b97/include/llama.h), [official `LibLlama.swift`](https://github.com/ggml-org/llama.cpp/blob/b2e5e9b28b2484fbf94b543432ece638996a8b97/examples/llama.swiftui/llama.cpp.swift/LibLlama.swift) | Chat-template application, tokenization, sampler chain, bounded decode, EOG handling, and symmetric sampler/batch/context/model/backend cleanup. ClipGum adds chunked prefill, byte/output caps, cancellation, and silent logging. |
| GGUF Swift package binding | [llama.swift `Package.swift`](https://github.com/mattt/llama.swift/blob/018619bf56f92cc85286150611609f456813826f/Package.swift), [llama.swift `Llama.swift`](https://github.com/mattt/llama.swift/blob/018619bf56f92cc85286150611609f456813826f/Sources/LlamaSwift/Llama.swift) | Prebuilt upstream XCFramework discovery and direct C API re-export. No remote inference client or high-level black-box wrapper is used. |
| SwiftLlama wrapper comparison | [SwiftLlama `Swiftllama.swift`](https://github.com/ShenghaiWang/SwiftLlama/blob/792181492beff9edba52314a040032cefb19edd6/Sources/SwiftLlama/Swiftllama.swift), [SwiftLlama `LlamaModel.swift`](https://github.com/ShenghaiWang/SwiftLlama/blob/792181492beff9edba52314a040032cefb19edd6/Sources/SwiftLlama/LlamaModel.swift) | Actor/stream boundary, low default temperature, fixed-seed sampling, and per-response cache clearing. ClipGum implements its own macOS 14 wrapper and does not adopt Combine/session history. |
| Prompt commands and schema dispatch | [Raycast Ollama professional command](https://github.com/raycast/extensions/blob/0b61ca53883ae7f8d571c4193c35270b982d0340/extensions/raycast-ollama/src/ollama-professional.tsx), [Raycast model streaming adapter](https://github.com/raycast/extensions/blob/0b61ca53883ae7f8d571c4193c35270b982d0340/extensions/raycast-ollama/src/models.ts), [Boop `ScriptManager.swift`](https://github.com/IvanMathy/Boop/blob/5cf6914381f6ed6ef004c3a7d470f241a248fcb6/Boop/Boop/System/ScriptManager.swift#L142-L171) | Stateless command-specific instructions, low-creativity editing, explicit stream mapping, and schema-oriented result handling. ClipGum uses native pure validators rather than Raycast's cloud/API runtime or Boop's JavaScript runtime. |
| Status item and marker filtering | [Maccy `AppDelegate.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/AppDelegate.swift#L11-L22), [Maccy `Clipboard.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift#L20-L31) | Strong `NSStatusItem` ownership and checking ignored types before content. Maccy's history timer was **not** adopted. No `accessBehavior` implementation was found at this revision; that gate comes from Apple. |
| Status-item/panel lifecycle comparison | [Ice `ControlItem.swift`](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/ControlItem/ControlItem.swift#L43-L135), [Ice `IceBar.swift`](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/UI/IceBar/IceBar.swift#L11-L42) | Compared explicit AppKit ownership and floating-panel configuration. Ice's larger machinery and GPL source were not copied. |
| Global hotkey | [AltTab `KeyboardEvents.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/KeyboardEvents.swift#L173-L200), [KeyboardShortcuts `HotKey.swift`](https://github.com/sindresorhus/KeyboardShortcuts/blob/772133d9dbe800fdac0473226822994c5c162c58/Sources/KeyboardShortcuts/HotKey.swift#L269-L283) | `RegisterEventHotKey`, event IDs, handler installation, and symmetric unregistration. No global keyboard monitor or CGEvent tap is used for shortcut detection. |
| Floating HUD | [Maccy `FloatingPanel.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/FloatingPanel.swift#L24-L51), [AltTab `TilesPanel.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/main-window/TilesPanel.swift#L1-L42) | Borderless key-capable `NSPanel`, status-bar level, active-Space behavior, focus-loss dismissal, and a local-only Escape monitor. |
| Paste synthesis | [Clipy `PasteService.swift`](https://github.com/Clipy/Clipy/blob/71b0e82623d5c73b4b717d81233eb78db8bbe258/Clipy/Sources/Services/PasteService.swift#L130-L151), [Maccy `Clipboard.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift#L123-L148) | Accessibility-gated ⌘V via key-down/key-up `CGEvent`s and a short focus handoff. ClipGum adds a pre-write permission guard and no automatic clipboard restoration. |
| URL query preservation | [Clipboard Cleaner `URLCleaner.swift`](https://github.com/thetoadsage/clipboard-cleaner/blob/936a4b357a6693ae7465feec1945bd4acbe25bc6/Sources/ClipboardCleanerCore/URLCleaner.swift#L128-L177) | Cross-check for deleting raw query pairs rather than serializing decoded `queryItems`. ClipGum adds embedded-URL scanning and fail-closed malformed-escape handling; no polling or automatic write was adopted. |
| Secret-rule benchmark | [Gitleaks `gitleaks.toml`](https://github.com/gitleaks/gitleaks/blob/5f6ec56cfa6f8c67648d863582c7ae2f206d5c1c/config/gitleaks.toml#L205-L219) | Benchmarked AWS key shape and keyword-scoped generic-secret approach. ClipGum uses a smaller deterministic rule set and no entropy/network step. |
| Marker convention | [Maccy README](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/README.md#ignore-custom-copy-types), [nspasteboard.org source](https://github.com/NSPasteboard/NSPasteboard.org) | Universal concealed/transient/auto-generated markers and legacy password-manager conventions. |

**Source-availability note:** Shottr and Sindre Sorhus's Pure Paste remain product benchmarks, but no verifiable public implementation repository for them was used. Raycast extension APIs are not treated as native `NSPanel` source. DevUtils' inspected old snapshot supplied no reusable inference, URL-cleaning, or secret-scrubbing implementation. Concrete low-level choices above come from linked public code and Apple documentation.

MLX Swift, MLX Swift LM/Examples, llama.cpp, llama.swift, SwiftLlama, Raycast Extensions, Maccy, Clipy, Boop, KeyboardShortcuts, Gitleaks, and Clipboard Cleaner are MIT-licensed at the inspected revisions. Ice and AltTab were architecture references only. Each upstream project retains its own license and copyright.
