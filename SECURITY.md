# Security Policy

## Supported Versions

Security updates are applied to the latest release only.

| Version        | Supported          |
| -------------- | ------------------ |
| latest release | :white_check_mark: |
| older releases | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in WhisPaste, **please do not open a public issue.**

Instead, report it privately via [GitHub Security Advisories](https://github.com/whispaste/whispaste/security/advisories/new).

### What to include

- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof of concept (if possible)
- The version(s) affected

### What to expect

- **Acknowledgment** within 48 hours of your report
- **Status update** within 7 days with an initial assessment
- **Fix timeline** communicated once the issue is confirmed — we aim to release a patch within 14 days for critical vulnerabilities
- **Credit** in the release notes (unless you prefer to remain anonymous)

If the vulnerability is declined, we will explain why.

## Scope

The following are in scope for security reports:

- The WhisPaste desktop application (Flutter)
- The auto-update mechanism (download verification, HTTPS enforcement)
- Local data storage (config, history database, audio cache)
- API key handling and credential storage
- WhisPaste API feedback endpoints (`api.whispaste.de`, `/v1/feedback`)

The following are **out of scope**:

- The landing page ([whispaste.de](https://whispaste.de)) — static site with no user data
- Third-party dependencies (report those to the upstream project)
- Social engineering or phishing attacks

## Security Practices

- App requests to public servers use HTTPS. Windows certificate validation can
  additionally retrieve signed revocation lists over HTTP; see
  [Windows certificate checks](NETWORK.md#windows-certificate-checks-triggered-by-https).
- Auto-update packages are cryptographically signed via EdDSA (Ed25519); model file downloads are verified via SHA-256 checksums
- API keys are stored in platform-native secure storage (OS keychain / credential manager)
- Crash reporting and performance traces via Sentry (EU data region) are **opt-out** — on by default, switched off in Settings → Privacy → "Error Reporting" (also offered on the onboarding Privacy step). Reports never contain audio or transcribed text: no screenshots, no view hierarchy, no default PII, events containing secrets (e.g. API keys) are dropped, the OS account name in file paths is replaced, switching it off also stops native crash and app-hang reports, and log breadcrumbs are stripped from performance traces
- Usage analytics (self-hosted Matomo) are anonymous and **opt-out** — on by default, switched off in Settings → Privacy → "Share anonymous usage statistics". Cookieless, no account, IP anonymised server-side, only aggregated event counters plus a weekly rotating pseudonym; never audio, text, history, tags or notes (see the privacy policy)
- Clipboard content is only used locally (pasting, restoring the previous clipboard, the in-memory clipboard history). It is never written to disk or sent anywhere. WhisPaste does not write dictation or clipboard content to the log. Where an error message could contain such content, only the error type is logged; every log line is also stripped of paths and secrets.
- The optional local automation API binds to loopback only and compares its bearer token in constant time
- **Keystroke undo on Linux (X11):** after an insert, for at most five minutes, WhisPaste reads the *times* of raw key presses and mouse clicks (XInput2) to tell whether you typed or clicked elsewhere before an undo. No key values, characters or click positions are read or stored, nothing is written to disk or sent anywhere, and the watcher is stopped again afterwards. Under Wayland it is not active at all. The undo keystroke (Ctrl+Z) only goes to windows known to be plain text targets; unknown windows and terminals get the clipboard path instead
- **Keystroke undo on Windows:** after an insert, for at most five minutes, WhisPaste installs low-level keyboard and mouse hooks that keep only the *times* of the last key press and click (and whether a click landed in a WhisPaste window), to tell whether you typed or clicked elsewhere before an undo. No key codes, characters or click positions are kept, nothing is written to disk or sent anywhere, and the hooks are removed again afterwards. If the hooks cannot be shown to have run without a gap since the insert, no Ctrl+Z is sent. Ctrl+Z only goes to programs known to be plain text targets; consoles, unknown programs and elevated windows get the clipboard path instead
- **Keystroke undo on macOS:** after an insert, for at most five minutes, WhisPaste keeps the *time* of the last mouse click that landed outside its own windows (a global event monitor for mouse clicks, which needs no permission), and reads the system's key idle time, to tell whether you typed or clicked elsewhere before an undo. No key codes, characters or click positions are kept, nothing is written to disk or sent anywhere, and the monitor is removed again afterwards. If the monitor cannot be installed, no Cmd+Z is sent. Cmd+Z only goes to apps known to be plain text targets; terminals, editors with a built-in terminal and unknown apps get the clipboard path instead
- **Clipboard history on Linux:** dictated text is written with the `x-kde-passwordManagerHint` hint, which only KDE's Klipper honours. Other clipboard managers (for example GPaste or CopyQ) can still record dictated text; turn off their history or delete the entry there. If WhisPaste cannot set the hint on the restored clipboard text, it restores the text as a plain write, which these managers may then record; the user's clipboard is kept in that case on purpose. The restored text is whatever was on the clipboard before, which can include a password copied earlier from a password manager; in that case it can end up in the clipboard manager's history
- Every host the app contacts on its own is listed in [`NETWORK.md`](./NETWORK.md)

## Audio Import Decoders on Linux

Voice-note import decodes files with libraries that WhisPaste neither bundles nor pins:

- Ogg/Opus and FLAC use the system `libopusfile`, `libogg` and `libFLAC`, declared as runtime dependencies of the `.deb` package. Their patch level is the one of the installed distribution.
- M4A/AAC uses GStreamer, loaded at runtime. `decodebin` picks any installed GStreamer plugin that can read the file, so the plugins on the system, not WhisPaste, decide what parses the audio.
- The imported file is first copied into the app's data folder. Its size and duration are capped before and during decoding.

Keep system packages up to date, and install only GStreamer plugin packages you trust.
