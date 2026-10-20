# Security Policy

## Supported Versions

Security updates are applied to the latest release only.

| Version        | Supported          |
| -------------- | ------------------ |
| latest (1.4.x) | :white_check_mark: |
| < 1.0          | :x:                |

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
- Supabase backend infrastructure (PostgREST endpoints, RLS policies, database)

The following are **out of scope**:

- The landing page ([whispaste.de](https://whispaste.de)) — static site with no user data
- Third-party dependencies (report those to the upstream project)
- Social engineering or phishing attacks

## Security Practices

- All network requests use HTTPS exclusively
- Auto-update packages are cryptographically signed via EdDSA (Ed25519); model file downloads are verified via SHA-256 checksums
- API keys are stored in platform-native secure storage (OS keychain / credential manager)
- Crash reporting and performance traces via Sentry (EU data region) are **opt-out** — on by default, switched off in Settings → Privacy → "Error Reporting" (also offered on the onboarding Privacy step). Reports never contain audio or transcribed text: no screenshots, no view hierarchy, no default PII, events containing secrets (e.g. API keys) are dropped, the OS account name in file paths is replaced, switching it off also stops native crash and app-hang reports, and log breadcrumbs are stripped from performance traces
- Usage analytics (self-hosted Matomo) are anonymous and **opt-out** — on by default, switched off in Settings → Privacy → "Share anonymous usage statistics". Cookieless, no account, IP anonymised server-side, only aggregated event counters plus a weekly rotating pseudonym; never audio, text, history, tags or notes (see the privacy policy)
- Clipboard content is only used locally (pasting, restoring the previous clipboard, the in-memory clipboard history). It is never written to disk or sent anywhere. WhisPaste does not write dictation or clipboard content to the log. Where an error message could contain such content, only the error type is logged; every log line is also stripped of paths and secrets.
- The optional local automation API binds to loopback only and compares its bearer token in constant time
- **Clipboard history on Linux:** dictated text is written with the `x-kde-passwordManagerHint` hint, which only KDE's Klipper honours. Other clipboard managers (for example GPaste or CopyQ) can still record dictated text; turn off their history or delete the entry there. If WhisPaste cannot set the hint on the restored clipboard text, it restores the text as a plain write, which these managers may then record; the user's clipboard is kept in that case on purpose. The restored text is whatever was on the clipboard before, which can include a password copied earlier from a password manager; in that case it can end up in the clipboard manager's history
- Every host the app contacts on its own is listed in [`NETWORK.md`](./NETWORK.md)

## Audio Import Decoders on Linux

Voice-note import decodes files with libraries that WhisPaste neither bundles nor pins:

- Ogg/Opus and FLAC use the system `libopusfile`, `libogg` and `libFLAC`, declared as runtime dependencies of the `.deb` package. Their patch level is the one of the installed distribution.
- M4A/AAC uses GStreamer, loaded at runtime. `decodebin` picks any installed GStreamer plugin that can read the file, so the plugins on the system, not WhisPaste, decide what parses the audio.
- The imported file is first copied into the app's data folder. Its size and duration are capped before and during decoding.

Keep system packages up to date, and install only GStreamer plugin packages you trust.
