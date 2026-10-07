# Security Policy

## Supported Versions

Security updates are applied to the latest release only.

| Version        | Supported          |
| -------------- | ------------------ |
| latest (1.3.x) | :white_check_mark: |
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
- Crash reporting and performance traces via Sentry (EU data region) are **opt-out** — on by default, switched off in Settings → Privacy → "Error Reporting" (also offered on the onboarding Privacy step). Reports never contain audio or transcribed text: no screenshots, no view hierarchy, no default PII, events containing secrets (e.g. API keys) are dropped, and log breadcrumbs are stripped from performance traces
- Usage analytics (self-hosted Matomo) are anonymous and **opt-out** — on by default, switched off in Settings → Privacy → "Share anonymous usage statistics". Cookieless, no account, IP anonymised server-side, only aggregated event counters plus a weekly rotating pseudonym; never audio, text, history, tags or notes (see the privacy policy)
- The optional local automation API binds to loopback only and compares its bearer token in constant time
- Every host the app contacts on its own is listed in [`NETWORK.md`](./NETWORK.md)
