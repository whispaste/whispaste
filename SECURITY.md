# Security Policy

## Supported Versions

WhisPaste is currently in early development. Security updates are applied to the latest release only.

| Version       | Supported          |
| ------------- | ------------------ |
| latest (0.4.x)| :white_check_mark: |
| < 0.4         | :x:                |

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

- The WhisPaste desktop application (Go binary)
- The auto-update mechanism (download verification, HTTPS enforcement)
- Local data storage (config, history database, audio cache)
- API key handling and credential storage

The following are **out of scope**:

- The landing page ([whispaste.de](https://whispaste.de)) — static site with no user data
- Third-party dependencies (report those to the upstream project)
- Social engineering or phishing attacks

## Security Practices

- All network requests use HTTPS exclusively
- Auto-update downloads are verified via SHA-256 checksums
- API keys are stored locally in user-scoped config files, never transmitted to third parties
- No telemetry or analytics data is collected
