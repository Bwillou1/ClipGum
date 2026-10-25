# Enterprise deployment and MDM policy

ClipGum supports read-only managed preferences on macOS 14+ Apple Silicon. The app reads the effective values through `CFPreferencesCopyAppValue` and forced-key state through `CFPreferencesAppValueIsForced`, using the application bundle identifier `com.clipgum.ClipGum`. This includes the managed preferences domain backed by `/Library/Managed Preferences/` when a profile is installed.

ClipGum never writes to the managed domain, installs a profile, starts a preference watcher, or polls for changes. Values are read at launch, when Settings appears, and again at explicit action boundaries.

## Keys

| Key | Type | Effect when true |
| --- | --- | --- |
| `DisableExternalLLM` | Boolean | Locks inference to local on-device models. ClipGum has no external inference backend or cloud fallback. |
| `ForceSecretRedaction` | Boolean | Applies strict deterministic redaction of API keys, tokens, internal hostnames, and valid IPv4 addresses immediately before every copy/paste write, including **Paste Original** and the CLI output path. Rich HTML/RTF payloads become redacted plain text so an alternate flavor cannot bypass the policy. |
| `DisableCustomScripts` | Boolean | Prevents custom JavaScript from being added, enabled, or tested. Deterministic regex rules remain available. |
| `LockTelemetry` | Boolean | Forces diagnostics off, clears volatile counters, and disables the opt-in control. ClipGum has no telemetry uploader. |

A forced key displays a lock badge in the HUD and in Preferences → **Enterprise**. A false value without a forced profile does not create a lock badge. Policy checks do not read clipboard content.

## Example profile payload

The following is a documentation fragment, not a profile to install blindly. Have your MDM administrator sign, scope, and test a complete `.mobileconfig` in a non-production group first.

```xml
<dict>
  <key>PayloadType</key><string>com.clipgum.ClipGum</string>
  <key>PayloadIdentifier</key><string>com.example.clipgum.policy</string>
  <key>PayloadUUID</key><string>REPLACE-WITH-A-UUID</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>DisableExternalLLM</key><true/>
  <key>ForceSecretRedaction</key><true/>
  <key>DisableCustomScripts</key><true/>
  <key>LockTelemetry</key><true/>
</dict>
```

## Deployment protocol

1. Sign and notarize the release with the organization’s Developer ID and notary profile; do not use ad-hoc CI signatures for users.
2. Install the profile on a test Mac and confirm forced values with `CFPreferences`/the Enterprise pane, not by editing the app's ordinary defaults.
3. Verify that a forced redaction policy affects Copy Result, Paste Cleaned, Paste Original, Services, and any CLI pipeline that writes to `pbcopy`.
4. Verify that custom scripts cannot be enabled and that telemetry cannot be enabled.
5. Test revocation and profile removal in a fresh user profile. Do not claim MDM behavior from a unit-test `UserDefaults` suite alone.

## Network and content boundaries

Managed preferences do not grant network access to JavaScript. The app’s network client is limited to explicit Sparkle update checks and verified model downloads. Clipboard text, transformed output, regex tokens, and session mappings are never included in diagnostics or network requests. Enterprise policy values themselves are non-content booleans.
