# ClipGum

**Phase 5 — secure public-beta distribution, signed updates, privacy audit, and verified local model acquisition for macOS 14+ on Apple Silicon.**

Copy normally, press **⌘⇧V**, inspect deterministic or locally generated output, then choose exactly what happens next. ClipGum still does not watch clipboard changes, keep history, perform cloud inference, or rewrite the pasteboard on its own.

- **Platform:** Swift / SwiftUI / AppKit, macOS 14+
- **Inference:** optional local MLX or GGUF on Apple Silicon; never required for mechanical actions
- **Build:** Swift Package Manager with pinned direct dependencies
- **UI:** one `NSStatusItem`, one Carbon global hotkey, one floating `NSPanel`
- **License:** Apache-2.0 (see [`LICENSE`](LICENSE))

## Phase 6 — GA, extensibility, and ecosystem

Phase 6 adds a shared `ClipGumCore` library and these production surfaces:

- **Custom Rules & Scripts** — Preferences → Rules provides regex and Boop-style `main(input)` JavaScript editing, an off-main-actor playground, and checksummed JSON import/export. JavaScript has no filesystem, network, environment, process, or pasteboard bridge and fails closed without the native 250 ms watchdog. See [`PLUGINS.md`](PLUGINS.md).
- **CLI** — the standalone `clipgum` executable supports `clean-secrets`, `sanitize-text`, `strip-urls`, `json-to-ts`, and `extract-table`, with stdin piping, mapped file input, `--raw`, `--diff`, `--json`, and `--locale`. Build with `swift build --product clipgum`; see [`Tools/clipgum-cli/clipgum.1`](Tools/clipgum-cli/clipgum.1).
- **Shortcuts and Services** — native App Intents expose Sanitize Text, Extract Table, Redact Secrets, and Transform with Local Model. The Services menu provides **Clean & Paste with ClipGum** for an explicitly selected text service. Deep links open settings only and never carry content.
- **Performance** — model idle offload uses a one-shot cancellable compactor, deterministic work has no idle scheduler, and thermal pressure caps or skips local generation.
- **Enterprise** — read-only CFPreferences policy enforcement covers `DisableExternalLLM`, `ForceSecretRedaction`, `DisableCustomScripts`, and `LockTelemetry`, with managed lock badges in the HUD and Settings. See [`ENTERPRISE.md`](ENTERPRISE.md).

No runtime performance, fresh-profile Shortcuts, real MDM, Developer ID, notarization, or Apple Silicon model outcome is claimed from source or Linux checks alone. The macOS CI suite compiles and tests these surfaces; hardware/profile validation remains a release checklist item.

## Explicit workflow

1. Copy one plain-text (`public.utf8-plain-text`), HTML (`public.html`), or RTF (`public.rtf`) item in any app.
2. Press **⌘⇧V**, or choose **Smart Paste…** from ClipGum's menu bar item.
3. ClipGum checks pasteboard access and sensitive-type metadata, then reads the supported flavors once from that single item.
4. `RuleCleaningService` immediately produces a deterministic Before/After preview from the visible plain text. No model is loaded by this step.
5. Optionally select an action and choose **Run**:
   - Mechanical actions execute synchronously without calling an inference engine.
   - LLM actions require an explicitly selected local model and stream provisional output.
6. Review the exact diff and validation messages, then choose:
   - **Paste Cleaned** — writes approved plain output or one-item plain/HTML/RTF output and sends ⌘V to the previous app.
   - **Copy Result** — writes only the approved output; paste it yourself.
   - **Paste Original** — writes the captured original plain text and sends ⌘V.
   - **Cancel**, **Escape**, or an outside click — closes without a pasteboard write.

Pressing ⌘⇧V while the palette is open dismisses it without another clipboard read. Copy/Paste Cleaned is disabled during streaming and after any error-severity validation failure.

### Deliberate non-goals

There is no clipboard history, polling loop, launch-time clipboard read, lossless round-trip of every original rich-text flavor, automatic/background multi-item merging, automatic pasteboard restoration, telemetry, cloud inference, automatic model download, or autonomous agent/tool execution. Chain Copy is a separate opt-in, volatile session described below. “Paste Original” means the original **plain-text representation**, not every original RTF/HTML representation.

## Two-stage execution pipeline

### Stage 1: deterministic and engine-free

| Action | Implementation | Calls an engine? |
| --- | --- | --- |
| Clean Plain Text + Redact | URL de-tracking → regex secret reduction | Never |
| URL Clean | Raw-byte tracker removal only | Never |
| Regex Secret Scrub | Secret rules only | Never |
| Share-Ready / Restore Original Identifiers | Volatile bidirectional synthetic-identifier session | Never |
| JSON Pretty / Minify | Native bounded parser → AST → renderer | Never |
| JSON → TypeScript | Native JSON AST → deterministic type inference/emission | Never |
| Log / Stack Trace Scrub | ANSI/frame/timestamp cleanup → exact secret/IP redaction | Never |
| Bash Inspect | Pure lexer and deterministic risk rules; no execution API | Never |
| PDF Line-Wrap Repair | Blank-line-aware hard-wrap and soft-hyphen repair | Never |
| Rich Text Sanitizer | Bounded HTML token scan → semantic allowlist → native AppKit RTF | Never |
| Table Convert | HTML/TSV/CSV/semicolon-CSV/Markdown/aligned-ASCII extraction → deterministic CSV/TSV/Markdown | Never |

`SmartPastePipeline.mechanicalResult` is synchronous. Its tests use a mock engine and verify that none of these paths calls `transform`.

### Stage 2: explicitly selected local LLM

- **CORRECTION ONLY — FRANÇAIS / ENGLISH** — spelling/grammar/punctuation in the source language while instructing the model to retain facts, numbers, tone, style, code, formulas, and redaction markers.
- **REWRITE** — professional, concise wording with no injected data, facts, numbers, examples, citations, URLs, or code.
- **PROFESSIONAL EMAIL** — clear professional editing without new recipients, facts, commitments, approvals, dates, deadlines, greetings, signatures, or next steps.
- **SLACK / CHAT SUMMARY** — action-oriented Decisions/Open actions/Blockers only when supported by the source; proposals and questions do not become commitments.
- **TABLE TO CSV** — the Phase 2 LLM route remains for compatibility; the Phase 4 **Table Convert** action is the deterministic Office workflow.
- **BASH PARAMETER EXPLANATION** — concise token/flag/redirection/pipeline explanation from an inert command string. The independent deterministic inspector owns every danger finding; model output cannot downgrade it and is never executed.

System instructions and untrusted input remain separate arguments through `InferenceEngine`. Clipboard text is not interpolated into the instruction template. Before any LLM call, the full deterministic URL/secret pipeline runs; the engine receives only that cleaned text, not the raw clipboard value.

Streaming chunks are provisional UI state. A final `TransformationResult` is emitted only after output-budget enforcement, transport-wrapper removal, and post-validation.

## Phase 3 developer workflows

The HUD exposes Share-Ready actions for general text and adds JSON, shell, or log/stack-trace actions only when the deterministic content classifier matches that input. These schemas describe the captured plain text, not an implicit clipboard watcher:

| Action | Input and options | Preview output | Failure behavior |
| --- | --- | --- | --- |
| Share-Ready | Any captured text | Consistent fictional identifiers; replacement count | Existing text remains recoverable through Paste Original |
| Restore Original Identifiers | A returned assistant snippet captured in the same app session | Synthetic values replaced by their real mappings | Unknown/cleared mappings remain unchanged |
| JSON Pretty | One JSON value; 2-space, 4-space, or tab indentation | Object-order- and number-lexeme-preserving JSON | Exact 1-based line/column error; deterministic preview restored |
| JSON Minify | One JSON value | Compact JSON with no insignificant whitespace | Same native parser error path |
| JSON → TypeScript | One JSON value; legal root name; export on/off | Deterministic `interface`/`type` declarations | Malformed JSON and invalid/reserved root names are rejected |
| Log / Stack Trace Scrub | Terminal logs, stack traces, ANSI-colored text | Cleaned log with stack noise/timestamps removed and sensitive values redacted | Text-only transform; no parser/inference fallback |
| Bash Inspect | Shell-shaped text | Risk findings plus token/parameter report | Unmatched quotes produce a visible warning; covered raw risks still run |
| Bash Explain | Shell-shaped text plus an explicitly loaded local model | Bounded plain-text parameter explanation | Deterministic baseline restored on stream/model/validation failure |

### Native JSON and TypeScript boundaries

`Services/Dev/JSON` contains a native recursive-descent parser, AST, renderer, and TypeScript inferencer. It does not use JavaScript, an LLM, or floating-point number conversion. Strings support escaped control characters and UTF-16 surrogate pairs; malformed escapes, unpaired surrogates, leading zeros, trailing commas, and trailing content are rejected.

- Maximum JSON input: **2 MiB UTF-8**.
- Maximum container nesting: **256 levels**.
- Errors report a 1-based line and Unicode-scalar column.
- Pretty rendering preserves object member order and validated number lexemes, including large integers and exponent spelling.
- TypeScript array inference merges object shapes, marks missing properties optional, preserves deterministic union order, and emits `unknown[]` for empty arrays.
- Property names are quoted when necessary. Root names must be non-reserved identifiers beginning with a letter, `_`, or `$`.

TypeScript output is a structural approximation, not a runtime schema validator. For example, mixed values can produce unions and a property present only as `null` remains `null` rather than being assumed to have another type.

### Share-Ready volatile-session security model

`ShareReadySession` keeps two lock-protected dictionaries in process memory: real+category → fictional and fictional → real. It never writes its mapping tables to preferences, files, bookmarks, logs, or model storage. A pasteboard write of preview text still requires the normal explicit Copy/Paste choice.

Detected categories include:

- RFC1918 IPv4 addresses, `localhost`, and `::1`.
- Internal endpoints such as `api.corp`, `service.internal`, `host.local`, and `db.corp.net`.
- macOS `/Users/<name>` path prefixes.
- Environment/JSON-style credential assignments, bearer values, AWS access-key shapes, URL basic-auth userinfo, and private-key blocks.

Replacements are stable within the session and avoid collisions with source text and existing synthetic values. Examples include `db.example.test`, `host-1.example.test`, `/Users/[USER]/…`, `[ENV_VALUE_1]`, and `[CREDENTIAL_1]`. Repeated occurrences of the same real value in one category receive the same synthetic value.

To restore a returned assistant snippet, copy that snippet, invoke ⌘⇧V, and explicitly run **Restore Original Identifiers**. Only identifiers already present in the live mapping are restored. **Clear Share-Ready** immediately drops both directions and resets ordinal assignment; app quit does the same. Clearing does not rewrite text already shown or exported. Dismissing the HUD alone does not clear the session.

This is deterministic pseudonymization, **not encryption, DLP, or a guarantee that every secret/internal identifier was found**. Review the preview before sharing. Once mappings are cleared or the app exits, restoration is intentionally impossible.

### Bash inspection has zero execution capability

`Services/Dev/Bash` performs shell-inspired lexing and deterministic checks only. It does not call `Process`, `system`, `popen`, a shell, AppleScript, or a command runner; command substitution is treated as text. No parsed command or pipeline segment is executed or piped into a shell.

Covered high-visibility findings include:

- `rm` with recursive and force flags, including separated/combined short flags and long forms.
- `dd`, `mkfs`/`mkfs.*`, and `mke2fs`.
- The canonical `:(){ :|:& };:` fork-bomb shape, ignoring whitespace.
- `curl`/`wget` piped to `bash`, `sh`, `zsh`, or `ksh`, including an elevated shell.
- `sudo`, `doas`, and `pkexec` elevation requests.

The red **DANGER** badge and finding list are computed independently of the local LLM and remain attached to the original inspection. Bash Explain is advisory and cannot suppress them. The lexer intentionally is not a complete Bash grammar; obfuscation, aliases, expansions, and novel destructive commands can evade rules. **No finding is not a safety proof—review commands independently and run them only outside ClipGum.**

### Chain Copy: explicit, opt-in accumulation

1. Invoke ClipGum on a captured clip and choose **Chain Copy**. This starts a volatile session with the captured original text; it does not write the pasteboard.
2. Copy the next selection and invoke ⌘⇧V again. Each addition requires this explicit invocation and the same sensitive-marker/access checks. Exact duplicate text is ignored.
3. Toggle clip inclusion, move clips up/down, and select newline, comma (`,`, no added space), or Markdown-bullet (`- `) joining.
4. Review the live combined preview. Selection and reordering never write the pasteboard.
5. Choose **Copy Combined & Clear** for the single explicit write, **Clear Chain** to discard, or **Close & Continue** to keep accumulating. App quit also clears the chain.

Chain Copy is not a history browser: it contains only clips explicitly added after opt-in, and there is no persistent chain storage.

### Log cleanup

`LogScrubber` removes ANSI CSI/OSC escapes, covered Java/JavaScript/Python/native stack-frame lines, and leading ISO, bracketed, bare-time, or syslog timestamps. Existing secret rules retain the exact `[SECRET_REDACTED]` replacement. The log pass additionally covers IPv4 loopback/unspecified/link-local addresses, IPv6 loopback, link-local, and unique-local address shapes. Public IPs and non-frame message lines remain in the preview.

## Phase 4 Office workflows

### Multi-flavor document architecture

`PasteboardDocument` is an immutable, one-item capture with optional plain text, HTML, and RTF. `SystemPasteboard.readDocumentForExplicitUserAction()` remains inside the sole explicit-trigger route and checks access plus all sensitive markers **before reading any content flavor**. HTML-only and RTF-only items can supply visible preview text through the bounded HTML extractor or AppKit's `NSAttributedString` RTF decoder. Multiple pasteboard items are still rejected rather than merged.

`RichTextSanitizer` uses a 4 MiB-bounded, regex-free token scanner and an allowlist inspired by SwiftSoup's Cleaner/Safelist separation. It preserves `strong`/`b`, `em`/`i`, safe links, `h1`–`h3`, ordered/unordered lists, paragraphs, and basic table semantics. Script/style/head content, comments, inline CSS, backgrounds, and source font/spacing containers are removed or unwrapped. Only `http`, `https`, `mailto`, and `tel` absolute schemes are accepted; relative links and fragments remain links, while malformed/control-character and script URLs lose `href`.

After sanitization, native AppKit `NSAttributedString` serialization regenerates RTF. `PasteboardPayload` carries plain text, sanitized HTML, and RTF together in **one `NSPasteboardItem`**, avoiding duplicate formatted-text items. The plain flavor must exactly match the visible approved preview or export falls back to plain text. This is semantic sanitization, not preservation of arbitrary original CSS, embedded objects, images, or every legacy pasteboard flavor.

**PDF Line-Wrap Repair** operates on text copied from a PDF, not on PDF files and not OCR. It joins hard wraps, removes soft hyphens at `word-` + newline + `break` boundaries with Unicode-aware letter checks, preserves blank-line paragraph boundaries, and retains accented text and list starts. It does not infer new paragraphs where the source has no blank line.

### Deterministic tables and locale-safe export

`Services/Office/Table` uses the same bounded token-scanner approach for HTML tables—never regex tag extraction—and strict character-level delimited parsing. Supported inputs are:

- HTML tables, with script/style/head suppression and rejection of nested/multiple tables and `rowspan`/`colspan` values other than 1.
- Excel-style TSV, comma CSV, semicolon CSV, Markdown, and whitespace-aligned ASCII with at least two spaces between columns.
- Consistent, nonempty row schemas only; malformed quotes and inconsistent column counts fail closed. Limits are 4 MiB UTF-8, 10,000 rows, and 256 columns.

The HUD shows the detected source and **rows × columns** before export. Choose **CSV**, **TSV**, or **Markdown**, plus **comma** or **semicolon** for CSV, then choose **Run** to regenerate the preview. Picker changes alone never write or transform the pasteboard.

CSV uses CRLF record separators, doubles quotes, and quotes delimiters, quotes, CR/LF, and comma-containing fields. Semicolon CSV deliberately quotes decimal-comma values such as `12,50` rather than converting them to a period. TSV uses LF records and quotes tabs/newlines/quotes. Markdown emits a deterministic header separator, escapes pipes/backslashes, and represents embedded cell newlines as `<br>`. No numeric locale normalization is performed.

### Office transforms and protected-data invariants

Professional Email and Slack/Chat Summary use the existing bounded local-inference path, temperature controls, cleaned-only input, and output limits. Their prompts prohibit invented facts, owners, commitments, and deadlines. Prompts alone are not treated as proof.

`DataInvariantValidator` performs deterministic post-model comparisons for Correction, Rewrite, Professional Email, and Slack/Chat Summary:

- Exact multisets of signed/grouped numbers, decimal commas or periods, percentages, times, ISO/numeric dates, and named English/French dates.
- Exact `$` and `€` symbol counts.
- Exact spreadsheet-formula tokens such as `=SUM(A1:A3)`, with quoted strings and nested parentheses handled by a character scanner.

A mismatch produces an error-severity issue, disables Copy/Paste, and displays the red **DATA DISCREPANCY · EXPORT BLOCKED** badge. Harmless reordering of protected tokens is allowed; changing their values is not. These checks supplement—not replace—secret regeneration checks, code preservation, semantic-divergence heuristics, and human review.

### Frontmost-app profiles without implicit reads

`OfficeAppProfileResolver` maps only `NSWorkspace.shared.frontmostApplication` metadata for Word, Excel, Outlook, Mail, Slack, Safari/Chrome/Firefox/Edge/Arc, and a fallback. The HUD can suggest Rich Text Sanitizer, PDF Repair, Table Convert, Professional Email, Slack Summary, Correction, or URL Clean when those actions are supported by the already-captured document. Selecting a suggestion does not run it. Profiling never accesses the pasteboard and cannot trigger a background read.

## Phase 5 public-beta hardening

### Signed distribution and release outputs

`Build/` contains the external-distribution pipeline. `Build/sign_app.sh` signs nested Sparkle helpers/XPC/frameworks inside-out with hardened runtime and then signs the main app with an exact minimal entitlement allowlist. No JIT, unsigned-executable-memory, library-validation, camera, microphone, or location exception is present. Sparkle helper entitlements are preserved rather than receiving the main app's network access.

`Build/release.sh` requires a Developer ID Application identity, a `notarytool` **Keychain profile**, a public HTTPS appcast URL, and Sparkle's public Ed25519 key. It produces a signed/notarized/stapled UDZO DMG containing the app and an `/Applications` drag-and-drop symlink, a `clipgum.rb` Homebrew Cask with automatic final-DMG SHA-256, a CycloneDX 1.5 SBOM, and a signed appcast. Credentials and private Ed25519 keys are never stored in the repository. Development packaging remains ad-hoc and leaves the updater disabled when public metadata is blank. See [`Build/README.md`](Build/README.md).

### Sparkle 2 updates

`Core/Updater/UpdateManager.swift` strongly retains `SPUStandardUpdaterController` and starts it only after validating:

- A strict-HTTPS feed with no URL userinfo.
- A canonical base64-encoded 32-byte Ed25519 `SUPublicEDKey`.
- `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`.
- Sparkle downloader XPC disabled, as required for a main app with network client.

The delegate also requires signed-appcast success and an HTTPS enclosure before proceeding, rejects non-HTTPS external release notes, removes cookies/authorization from update requests, and returns no system-profile keys or extra feed parameters. Stable uses Sparkle's default channel; beta explicitly adds only `beta`. Automatic checks default off and are applied **before** Sparkle's first scheduled cycle; daily/weekly frequency and manual Check for Updates are in Settings. Automatic downloading/installation is disabled. Release notes appear in Sparkle's standard window and a sanitized Settings viewer.

### Content firewall and Privacy & Audit

`Services/Diagnostics` has no uploader, endpoint, free-form event name, free-form error string, or persistent event store. Feature names and errors are closed enums; the only record inputs are an enum, elapsed nanoseconds, and an optional error enum. Payloads contain activation counts, nearest-rank p50/p95 latency, peak whole-process resident RAM, and fixed error counts. A second independent JSON-schema allowlist rejects unexpected fields and unknown enum strings.

Diagnostics are off by default in onboarding and Preferences. Disabling clears prior values. Privacy & Audit shows the exact canonical JSON and copies that same schema-validated text only after an explicit button action. **Clear All Data** clears diagnostic counters/latencies/errors/peak RAM and withdraws opt-in, while also clearing volatile preview, Chain Copy, and Share-Ready state. Downloaded models and ordinary preferences are not deleted. There is no app analytics/crash-reporting SDK; operating-system crash-report behavior remains subject to macOS's own privacy controls.

### First run, permissions, and verified models

The three-step walkthrough covers explicit ⌘⇧V-only capture, sensitive-marker refusal, no-write preview, Accessibility and Paste from Other Apps recovery, Input Monitoring guidance without an unnecessary prompt, Apple Silicon/unified-RAM readiness, verified weights, and diagnostics opt-in. The palette and onboarding show an **Offline / Local Only** shield for inference; only explicit updates/model downloads use networking.

Existing local models remain read-only and session-selected. Alternatively, select a local manifest conforming to [`Build/Models/manifest.schema.json`](Build/Models/manifest.schema.json), then separately choose Download & Verify. Manifest URLs must be HTTPS; filenames, counts, backend layout, total size, and RAM are validated before transport. An ephemeral cookieless/credentialless downloader cancels oversize responses and non-HTTPS redirects. Files are staged, streamed through SHA-256, and installed atomically; corrupt/tampered files and staging data are removed, and existing identifiers are not overwritten. No unverified publisher URL or hash is hard-coded.

### Licenses, SBOM, and validation

Settings → Licenses embeds ClipGum and third-party license/credits text for Sparkle, MLX, MLX Swift/LM, llama.swift, llama.cpp, Boop, Maccy, and PrismML Ternary Bonsai attribution. PrismML weights are optional external works, not bundled or relicensed. `Build/SBOM.json` records direct pins and the llama.cpp binary provenance. Pure Paste-style minimal-permission/zero-telemetry requirements are design references only; proprietary Pure Paste source was not inspected.

Phase 5 adds update-policy, diagnostics, model-integrity, onboarding/license, network-isolation, and entitlement tests. `Build/test_sparkle_tamper.sh` uses Sparkle's real `sign_update --verify` with a test-only key to accept intact and reject modified archives. [`Build/VALIDATION.md`](Build/VALIDATION.md), [`Build/FRESH_PROFILE.md`](Build/FRESH_PROFILE.md), and [`BETA_TESTING.md`](BETA_TESTING.md) distinguish automated coverage from real notarization, Gatekeeper, fresh-profile, physical-model, and full update-install outcomes.

## Build and runtime prerequisites

### For the app and deterministic tests

- macOS 14.0 or later to run.
- **Xcode 16.3 or newer** to build. The macOS 15.4 SDK is required at compile time for `NSPasteboard.accessBehavior`; deployment remains macOS 14.
- Swift Package Manager resolves:
  - `mlx-swift` **0.31.3**
  - `mlx-swift-lm` **2.31.3** (the corrected LM-only package manifest; earlier split tags retain stale non-LM target paths)
  - `mattt/llama.swift` at commit `018619bf56f92cc85286150611609f456813826f`, which re-exports llama.cpp **b10549**'s prebuilt XCFramework.
  - `sparkle-project/Sparkle` **2.10.0**, using its checksummed SPM binary target.

No model weights are bundled. Unit tests use mocks and do not download or load a model.

### Additional requirements for local inference

- An **Apple Silicon** Mac. Backends fail safely with `unsupportedArchitecture` elsewhere.
- A local model already acquired from a publisher you trust, or an explicit version-1 verified download manifest (see Phase 5 below):
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

Tests use unique **named pasteboards**, never `NSPasteboard.general`, so they do not overwrite the developer's real clipboard. The package script builds a release executable, embeds dependency resources and Sparkle, creates `build/ClipGum.app`, installs hardened-runtime/sandbox metadata, and ad-hoc signs it by default for local development. For Developer ID signing, notarization, DMG/Cask/SBOM, and signed appcast generation, use [`Build/README.md`](Build/README.md). Accessibility grants can be tied to a code signature, so macOS may ask again after rebuilding or moving an ad-hoc signed app.

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
| Input | 32 KiB UTF-8 default; embedded NUL rejected to prevent C-template truncation; actual MLX token count also preflighted |
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
- Exact protected-number/percentage/date, `$`/`€`, and spreadsheet-formula preservation for Correction, Rewrite, Professional Email, and Slack/Chat Summary, with a prominent discrepancy badge.
- Exact fenced-code-block and inline-code-span preservation.
- TSV/Markdown source-matrix extraction, CSV syntax/column validation, and exact cell/order comparison for Table to CSV.
- Semantic-overlap/edit-distance heuristics that emit review warnings or block severe divergence.

**Passing validation is not proof of factual or semantic equivalence.** Regex secret detection remains best-effort, and lexical overlap cannot detect every hallucination. The preview remains mandatory. Error-severity issues disable model-output export; **Use Deterministic** restores the Stage 1 result. Engine throws, including OOM, never emit a completed model result and restore that result automatically.

## Streaming UI and exact diff

The floating palette retains one observable session while tokens arrive. It provides:

- Live local-stream/chunk status and provisional-output labeling.
- Side-by-side Before/After and inline diff modes.
- Exact token/whitespace-preserving differences: red strikethrough for removals and green underline for additions.
- Copy/Paste/Paste Original/Cancel, content-sensitive developer controls, a deterministic shell-danger badge, and opt-in Chain Copy.

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

Before calling `string(forType:)` or `data(forType:)`, ClipGum inspects advertised types and **every item's types**. Any of these markers rejects the entire read:

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
- Writes exist only in `writeTextForExplicitUserAction` / `writeDocumentForExplicitUserAction`, called by Copy Result, Copy Combined & Clear, or an approved paste action. Rich output is written as one item; no action writes automatically after preview or app profiling.
- Mechanical actions do not load or call a model.
- Models load only after explicit file selection or an explicit LLM Run.
- MLX uses `.directory`, not a repository downloader. The main app's narrowly scoped network-client entitlement is used only by explicit Sparkle checks and the separate explicit verified-model downloader; clipboard, inference, transformation, diagnostics, and paste paths contain no network call sites.
- The sandbox adds user-selected read-only file access and the two Sparkle InstallerLauncher Mach lookups required by that network-capable process model. Sparkle's downloader XPC is disabled. There is no persistent bookmark entitlement.
- Preferences contain only temperature/token/idle, update-channel/frequency/opt-in, diagnostics-opt-in, and onboarding-completion settings. Clipboard data, prompts, output, model paths, Share-Ready mappings, diagnostic samples, and Chain Copy items are not persisted. Share-Ready mappings and chain items are cleared on quit.
- Clipboard contents are not logged. ClipGum also installs a no-op llama.cpp logger to avoid third-party stderr prompt/output leakage. Diagnostics use closed non-content enums and a second payload schema gate; no crash reporter or telemetry endpoint is registered.
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
│   ├── ClipGumApp.swift              # SwiftUI entry and Phase 5 settings scene
│   ├── AppDelegate.swift             # Explicit reads, action routing, fallback, model selection
│   └── MenuBarController.swift       # One NSStatusItem and model/RAM status
├── Core/
│   ├── Clipboard/                    # One-item document/payload gateway and sensitive markers
│   ├── Context/AppProfile.swift      # Local frontmost-app metadata and HUD suggestions
│   ├── ChainCopy/                    # Opt-in volatile accumulation, selection, ordering, joining
│   ├── Hotkeys/GlobalHotKey.swift    # Carbon ⌘⇧V registration and teardown
│   ├── Paste/PasteService.swift      # Explicit copy, Accessibility check, ⌘V posting
│   ├── ModelDownload/                # HTTPS manifests, bounded transport, SHA-256, atomic install
│   ├── Permissions/                  # Accessibility checks and permission recovery
│   ├── Security/                     # Shared strict-HTTPS URL policy
│   ├── Updater/                      # Sparkle controller, channels, signed-feed enforcement
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
│   ├── Dev/
│   │   ├── JSON/                     # Native AST/parser/renderer and TypeScript inference
│   │   ├── ShareReady/               # Volatile bidirectional fictional ↔ real mappings
│   │   ├── Bash/                     # Non-executing lexer, risk rules, and token report
│   │   ├── Logs/                     # ANSI/frame/timestamp/IP cleanup
│   │   └── DeveloperContentClassifier.swift
│   ├── Diagnostics/                  # Opt-in closed-schema counters, latency, RAM, error codes
│   ├── Office/
│   │   ├── RichText/                 # Bounded scanner, semantic cleaner, PDF repair, AppKit RTF
│   │   ├── Table/                    # HTML/delimited/ASCII extraction and deterministic formatters
│   │   └── Transforms/               # Number/date/currency/formula invariant validation
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
    ├── Palette/                      # Streaming preview, offline shield, danger badge, Chain Copy
    ├── Onboarding/                   # First-run trigger, permissions, readiness, verified download
    └── Settings/                     # Inference, Updates, Privacy & Audit, Licenses/SBOM

Tests/ClipGumTests/                   # 230 XCTest cases; no model weights required
Resources/                            # Info.plist and minimal sandbox entitlements
Build/                                # Signing/notary/DMG/Cask/SBOM/appcast and validation scripts
BETA_TESTING.md                       # Beta privacy guarantees, feedback, and test protocols
Scripts/package_app.sh                # Repeatable local .app packaging
```

Delayed work consists of the one-shot paste focus handoff and one-shot idle offload. Neither polls the pasteboard.

## Phase 7: explicit local handoff, mobile companion, and portability

- **Zero-cloud handoff:** the HUD's **Send Sanitized to Device** action starts a
  temporary Bonjour/AWDL session. Fresh X25519 keys, a mutually confirmed
  six-digit SAS, HKDF-separated keys, and ChaCha20-Poly1305 protect one bounded
  payload. There is no account, cloud relay, history sync, or background retry.
  See `P2P_SECURITY.md`.
- **iOS/iPadOS:** `Targets/ClipGumMobile/project.yml` describes the companion,
  Share Sheet Action Extension, and optional keyboard. They share the
  deterministic `ClipGumCore` engine; local CoreML is availability/resource
  gated and always has a deterministic fallback. See `MOBILE.md`.
- **Encrypted portability:** Rules settings exports a password-protected
  `.clipgum` archive using Argon2id and AES-256-GCM. A typed allow-list and
  export/import audit exclude clipboard history, Share-Ready mappings, and
  session/device secrets. See `PLUGINS.md`.
- **Regression/performance:** `Tests/Performance` and
  `Build/validate_phase7.sh` cover protocol, mobile declarations, deterministic
  benchmarks, virtual idle behavior, and SDK migration checks. Hardware timing,
  physical radio, and 72-hour results are not assumed; see
  `Build/phase7_benchmarks.md`.

## Tests and manual verification

The **230 XCTest cases** cover:

- All Phase 1 URL, secret, pasteboard-marker, access-policy, and explicit-paste behavior.
- Prompt contents/non-interpolation, configuration clamps, local identifiers, and safe OOM classification.
- Every mechanical engine bypass, cleaned-only model input, token/output bounds, streaming completion, and OOM before/during streaming.
- Numeric/code preservation, secret regeneration, redaction markers, semantic warnings/failures, CSV syntax/schema/cell equality, and output unwrapping.
- Exact diff reconstruction with insertions, removals, replacements, whitespace, punctuation, CRLF, and Unicode.
- Backend selection, idempotent loads, busy-state protection, configuration updates, idle offload, and OOM cleanup/status.
- Nested/malformed/bounded JSON, exact error locations, Unicode escapes, TypeScript unions/optional fields/names/options, and deterministic output.
- Share-Ready consistency, fictional ↔ real round trips, synthetic collisions, public-IP preservation, credential blocks, and clearing.
- All covered destructive Bash fixtures, benign lookalikes, quote/pipeline lexing, parse-warning fallback, content-sensitive action schemas, and engine bypass.
- Chain Copy opt-in, exact duplicates, selection, reorder boundaries, every delimiter, clearing, ANSI/frame/timestamp cleanup, and local/private IP redaction.
- Real-world PDF wraps/paragraphs/accents, messy browser HTML, safe links, malformed markup, native AppKit RTF bold/italic/link round-trips, and foreign-typography stripping.
- HTML/Excel/CSV/semicolon/Markdown/aligned-ASCII tables, exact RFC 4180 quoting, decimal commas, embedded quotes/newlines, deterministic output, and fail-closed spans/schemas.
- Number/percentage/date/currency/formula invariants, named English/French dates, discrepancy blocking, Office prompts, cleaned-only inference input, app profiles, HUD table options, and rich payload/plain-preview agreement.
- Multi-flavor one-item pasteboard reads/writes and Accessibility-denied rich-paste non-destructiveness.
- Fail-closed update metadata, Ed25519 key shape, stable/beta channels, default-off preferences, strict HTTPS, diagnostics schema/percentiles/clearing, model-manifest/RAM/byte/SHA/atomic-install behavior, onboarding/resources, exact entitlement allowlists, and zero-request copy/transform/paste isolation.

Before a release, manually verify on each supported macOS line and Apple Silicon target:

1. ⌘⇧V works from TextEdit, Safari, Terminal, and an IDE; a conflicting second app leaves the menu action usable.
2. Cancel, Escape, and outside click preserve the exact system pasteboard and release preview text.
3. Real password-manager copies marked concealed/transient never reach the preview.
4. `.ask`, `.alwaysAllow`, and `.alwaysDeny` pasteboard settings behave as documented.
5. Denied Accessibility leaves the pasteboard untouched; Copy Result still works.
6. Paste targets the app that was frontmost when ClipGum was invoked.
7. VoiceOver can reach Before/After text, validation messages, action picker, developer options, danger findings, Chain Copy controls, and every export/cancel action.
8. Complete the model evaluation checklist above for each shipping model/quantization.
9. Complete the notarized fresh-profile install, permission-recovery, offline-cycle, Clear All Data, stable/beta, and tampered-update protocols in `Build/FRESH_PROFILE.md`; record only observed outcomes.

## Open-source implementation references and credits

References are pinned to inspected revisions. ClipGum's coordinator, validation, UI, and wrappers are original; third-party runtime packages retain their own licenses. No GPL-licensed source from Ice or AltTab is incorporated.

| Mechanism | Studied source | What was adapted — and what was not |
| --- | --- | --- |
| MLX generation and model lifecycle | [MLX Swift LM `ChatSession.swift`](https://github.com/ml-explore/mlx-swift-lm/blob/25b00d4e22e61ec9c41efda47990cd2084ec87ff/Libraries/MLXLMCommon/ChatSession.swift), [MLX Examples `ChatModel.swift`](https://github.com/ml-explore/mlx-swift-examples/blob/378f2449c257788c5067b9f8b086731d76b39b33/Applications/LLMBasic/ChatModel.swift) | `ModelContainer`, `ChatSession`, `GenerateParameters`, and chunk streaming patterns. ClipGum uses only local directories, adds actual-token preflight and strict caps, and does not retain a conversation. |
| MLX unified-memory controls | [MLX Swift `Memory.swift`](https://github.com/ml-explore/mlx-swift/blob/61b9e011e09a62b489f6bd647958f1555bdf2896/Source/MLX/Memory.swift) | Explicit memory/cache limits, resident-memory qualification, and `clearCache()` after dropping the model container. |
| llama.cpp C API and Swift ownership | [llama.cpp `llama.h`](https://github.com/ggml-org/llama.cpp/blob/b2e5e9b28b2484fbf94b543432ece638996a8b97/include/llama.h), [official `LibLlama.swift`](https://github.com/ggml-org/llama.cpp/blob/b2e5e9b28b2484fbf94b543432ece638996a8b97/examples/llama.swiftui/llama.cpp.swift/LibLlama.swift) | Chat-template application, tokenization, sampler chain, bounded decode, EOG handling, and symmetric sampler/batch/context/model/backend cleanup. ClipGum adds explicit mmap loading, chunked prefill, byte/output caps, cancellation, and silent logging. |
| GGUF Swift package binding | [llama.swift `Package.swift`](https://github.com/mattt/llama.swift/blob/018619bf56f92cc85286150611609f456813826f/Package.swift), [llama.swift `Llama.swift`](https://github.com/mattt/llama.swift/blob/018619bf56f92cc85286150611609f456813826f/Sources/LlamaSwift/Llama.swift) | Prebuilt upstream XCFramework discovery and direct C API re-export. No remote inference client or high-level black-box wrapper is used. |
| SwiftLlama wrapper comparison | [SwiftLlama `Swiftllama.swift`](https://github.com/ShenghaiWang/SwiftLlama/blob/792181492beff9edba52314a040032cefb19edd6/Sources/SwiftLlama/Swiftllama.swift), [SwiftLlama `LlamaModel.swift`](https://github.com/ShenghaiWang/SwiftLlama/blob/792181492beff9edba52314a040032cefb19edd6/Sources/SwiftLlama/LlamaModel.swift) | Actor/stream boundary, low default temperature, fixed-seed sampling, and per-response cache clearing. ClipGum implements its own macOS 14 wrapper and does not adopt Combine/session history. |
| Prompt commands and schema dispatch | [Raycast Ollama professional command](https://github.com/raycast/extensions/blob/0b61ca53883ae7f8d571c4193c35270b982d0340/extensions/raycast-ollama/src/ollama-professional.tsx), [Raycast model streaming adapter](https://github.com/raycast/extensions/blob/0b61ca53883ae7f8d571c4193c35270b982d0340/extensions/raycast-ollama/src/models.ts), [Boop `ScriptManager.swift`](https://github.com/IvanMathy/Boop/blob/5cf6914381f6ed6ef004c3a7d470f241a248fcb6/Boop/Boop/System/ScriptManager.swift#L142-L171) | Stateless command-specific instructions, low-creativity editing, explicit stream mapping, and schema-oriented result handling. ClipGum uses native pure validators rather than Raycast's cloud/API runtime or Boop's JavaScript runtime. |
| Stateless developer transformations | [Boop `FormatJSON.js`](https://github.com/IvanMathy/Boop/blob/5cf6914381f6ed6ef004c3a7d470f241a248fcb6/Boop/Boop/scripts/FormatJSON.js), [Boop `MinifyJSON.js`](https://github.com/IvanMathy/Boop/blob/5cf6914381f6ed6ef004c3a7d470f241a248fcb6/Boop/Boop/scripts/MinifyJSON.js) | Benchmarked supplied-text-only parse → serialize transforms with no persistent document state. ClipGum uses its own bounded native Swift AST/parser instead of Boop's JavaScript runtime. |
| JSON type inference and TypeScript emission | [quicktype `Inference.ts`](https://github.com/glideapps/quicktype/blob/c39af7d303b025280e2668a1b2d29913093593c9/packages/quicktype-core/src/input/Inference.ts), [quicktype `TypeScriptRenderer.ts`](https://github.com/glideapps/quicktype/blob/c39af7d303b025280e2668a1b2d29913093593c9/packages/quicktype-core/src/language/TypeScriptFlow/TypeScriptRenderer.ts) | Studied object-shape unification, optional properties, unions, and separation of inferred types from legal emitted names. ClipGum implements a smaller deterministic Swift inferencer and does not embed quicktype. |
| Shell token/operator explanation | [explainshell `matcher.py`](https://github.com/idank/explainshell/blob/827ebe38da9822a10e89946551e377330a9de35e/explainshell/matcher.py), [explainshell `models.py`](https://github.com/idank/explainshell/blob/827ebe38da9822a10e89946551e377330a9de35e/explainshell/models.py) | Studied token/source-span grouping, operators/redirections, option matching, and explicit unknown-span behavior as an architecture reference. No bashlex, man-page database, subprocess, or GPL source is incorporated; ClipGum's lexer and deterministic safety layer are original Swift. |
| Semantic HTML cleaning and tokenization | [SwiftSoup `Cleaner.swift`](https://github.com/scinfu/SwiftSoup/blob/e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f/Sources/Cleaner.swift), [SwiftSoup `Tokeniser.swift`](https://github.com/scinfu/SwiftSoup/blob/e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f/Sources/Tokeniser.swift), [SwiftSoup `Entities.swift`](https://github.com/scinfu/SwiftSoup/blob/e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f/Sources/Entities.swift) | Studied allowlist element/attribute copying, token boundaries, entity handling, and whitespace treatment. ClipGum uses an original bounded 4 MiB scanner/semantic serializer with no browser execution or SwiftSoup dependency; regex tag extraction is not used. |
| Multi-flavor pasteboard items | [Maccy `Clipboard.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift), [Clipy `PasteboardContent.swift`](https://github.com/Clipy/Clipy/blob/9bfd74baab113db41c9dfd45b4b9bbfef24d2752/Clipy/Sources/Models/PasteboardContent.swift) | Studied explicit flavor data capture and `NSPasteboardItem` reconstruction. ClipGum reads only after its marker gate and writes plain/HTML/RTF as one item; no history timer, multi-item grouping, or automatic paste was adopted. |
| Signed updater and sandbox process model | [Sparkle 2.10.0 `SPUUpdaterDelegate.h`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUpdaterDelegate.h), [Sparkle `SPUUpdater.m`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUpdater.m), [Maccy `SoftwareUpdater.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/SoftwareUpdater.swift) | Studied retained standard-controller/delegate patterns, KVO readiness, channels, EdDSA, signed-feed policy, and InstallerLauncher entitlements. ClipGum adds strict startup validation, no profile parameters, default-off checks, and disables downloader XPC because explicit model acquisition requires main-app network client. |
| Status item and marker filtering | [Maccy `AppDelegate.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/AppDelegate.swift#L11-L22), [Maccy `Clipboard.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift#L20-L31) | Strong `NSStatusItem` ownership and checking ignored types before content. Maccy's history timer was **not** adopted. No `accessBehavior` implementation was found at this revision; that gate comes from Apple. |
| Status-item/panel lifecycle comparison | [Ice `ControlItem.swift`](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/ControlItem/ControlItem.swift#L43-L135), [Ice `IceBar.swift`](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/UI/IceBar/IceBar.swift#L11-L42) | Compared explicit AppKit ownership and floating-panel configuration. Ice's larger machinery and GPL source were not copied. |
| Global hotkey | [AltTab `KeyboardEvents.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/KeyboardEvents.swift#L173-L200), [KeyboardShortcuts `HotKey.swift`](https://github.com/sindresorhus/KeyboardShortcuts/blob/772133d9dbe800fdac0473226822994c5c162c58/Sources/KeyboardShortcuts/HotKey.swift#L269-L283) | `RegisterEventHotKey`, event IDs, handler installation, and symmetric unregistration. No global keyboard monitor or CGEvent tap is used for shortcut detection. |
| Floating HUD | [Maccy `FloatingPanel.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/FloatingPanel.swift#L24-L51), [AltTab `TilesPanel.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/main-window/TilesPanel.swift#L1-L42) | Borderless key-capable `NSPanel`, status-bar level, active-Space behavior, focus-loss dismissal, and a local-only Escape monitor. |
| Paste synthesis | [Clipy `PasteService.swift`](https://github.com/Clipy/Clipy/blob/71b0e82623d5c73b4b717d81233eb78db8bbe258/Clipy/Sources/Services/PasteService.swift#L130-L151), [Maccy `Clipboard.swift`](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift#L123-L148) | Accessibility-gated ⌘V via key-down/key-up `CGEvent`s and a short focus handoff. ClipGum adds a pre-write permission guard and no automatic clipboard restoration. |
| URL query preservation | [Clipboard Cleaner `URLCleaner.swift`](https://github.com/thetoadsage/clipboard-cleaner/blob/936a4b357a6693ae7465feec1945bd4acbe25bc6/Sources/ClipboardCleanerCore/URLCleaner.swift#L128-L177) | Cross-check for deleting raw query pairs rather than serializing decoded `queryItems`. ClipGum adds embedded-URL scanning and fail-closed malformed-escape handling; no polling or automatic write was adopted. |
| Secret-rule benchmark | [Gitleaks `gitleaks.toml`](https://github.com/gitleaks/gitleaks/blob/5f6ec56cfa6f8c67648d863582c7ae2f206d5c1c/config/gitleaks.toml#L205-L219) | Benchmarked AWS key shape and keyword-scoped generic-secret approach. ClipGum uses a smaller deterministic rule set and no entropy/network step. |
| Marker convention | [Maccy README](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/README.md#ignore-custom-copy-types), [nspasteboard.org source](https://github.com/NSPasteboard/NSPasteboard.org) | Universal concealed/transient/auto-generated markers and legacy password-manager conventions. |

| Local peer transport | [Apple Network.framework `NWParameters.includePeerToPeer`](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer), [WWDC19 Building Custom Networking Protocols](https://developer.apple.com/videos/play/wwdc2019/713/) | Studied Bonjour browser/listener and peer-to-peer parameter patterns. ClipGum adds its own bounded wire protocol, explicit lifetime, mutual SAS, and ephemeral payload encryption; no proprietary networking implementation was inspected. |
| Password-based portable archives | [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.txt), [Argon2 Swift `v0.1.0`](https://github.com/colt3k/argon2-swift/tree/bcf667c8ee59ad6014bdac1474b5e717a0b95844) | Used the standardized Argon2id profile and pinned pure-Swift implementation, with bounded parameters and CryptoKit AES-GCM. Archive framing, strict schema, audits, and UI are ClipGum-specific. |

**Source-availability note:** Shottr and Sindre Sorhus's Pure Paste remain product benchmarks, but no verifiable public implementation repository for them was used. Raycast extension APIs are not treated as native `NSPanel` source. DevUtils' inspected old snapshot supplied no reusable inference, URL-cleaning, or secret-scrubbing implementation. Concrete low-level choices above come from linked public code and Apple documentation.

MLX Swift, MLX Swift LM/Examples, llama.cpp, llama.swift, Sparkle, SwiftLlama, SwiftSoup, Raycast Extensions, Maccy, Clipy, Boop, KeyboardShortcuts, Gitleaks, and Clipboard Cleaner are MIT-licensed at the inspected revisions. quicktype is Apache-2.0. Ice, AltTab, and GPL-3.0 explainshell were architecture references only; no explainshell source is incorporated. Each upstream project retains its own license and copyright.
