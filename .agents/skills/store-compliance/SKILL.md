---
name: store-compliance
description: >
  Microsoft Store compliance and multi-channel deployment readiness checker.
  Invoke before any release tag creation, Store submission, or when deployment
  artifacts are modified (MSIX manifest, installer, release workflow).
  Checks MSIX manifest, privacy policy, logo assets, network security,
  auto-update behavior, and deployment channel completeness.
---

# Store Compliance Skill — WhisPaste

## ⚡ MANDATORY: When to invoke this skill

You **MUST** invoke this skill — without being asked — when **any** of these conditions is true:

- A release tag is about to be created
- A Microsoft Store submission is being prepared
- Changes are made to: `msix/AppxManifest.xml`, `installer/whispaste.nsi`, `.github/workflows/release.yml`
- MSIX packaging, logo assets, or privacy policy content is modified
- A deployment channel (NSIS, portable, MSIX) is added or changed

**ALWAYS announce "🏪 Store-Compliance-Check wird durchgeführt..." before starting.** NEVER skip, summarize, or defer this check. This is not optional.

---

## 1. MSIX Manifest Checklist

Audit `msix/AppxManifest.xml` for the following:

- [ ] **Identity.Name** — MUST be a valid Store-registered package name
- [ ] **Identity.Publisher** — MUST match the certificate subject exactly
- [ ] **Identity.Version** — MUST use 4-part format `X.Y.Z.0` (last segment MUST be `0` for Store)
- [ ] **TargetDeviceFamily** — MUST be `Windows.Desktop`
- [ ] **MinVersion** — MUST be `10.0.17763.0` (Windows 10 1809) or higher
- [ ] **Capabilities** — MUST include `runFullTrust` for Win32 bridge apps
- [ ] **Logo assets** — every `<Logo>` and `<uap:DefaultTile>` path in the manifest MUST reference an existing file under `msix/Assets/`
- [ ] **DisplayName / Description** — MUST be non-empty and match Partner Center listing

---

## 2. Privacy Policy

- [ ] Privacy policy MUST exist at a publicly accessible HTTPS URL
- [ ] Policy MUST cover:
  - Audio recording (microphone access and local processing)
  - API data transmission (audio sent to OpenAI Whisper API)
  - Local storage (config, history database, audio cache)
  - Third-party services used (OpenAI, GitHub for updates)
- [ ] Privacy policy URL MUST be provided in Microsoft Partner Center listing
- [ ] SHOULD provide both EN and DE versions of the policy

---

## 3. Store Logo Assets

All assets reside in `msix/Assets/`. Verify each file exists and has the correct dimensions:

| Asset | Size | Required | Manifest reference |
|-------|------|----------|--------------------|
| `StoreLogo.png` | 50×50 | **MUST** | `Properties > Logo` |
| `Square44x44Logo.png` | 44×44 | **MUST** | `Applications > VisualElements` |
| `Square150x150Logo.png` | 150×150 | **MUST** | `Applications > VisualElements` |
| `Wide310x150Logo.png` | 310×150 | **SHOULD** | `uap:DefaultTile` |
| `Square310x310Logo.png` | 310×310 | **SHOULD** | `uap:DefaultTile` |

Additional requirements:
- [ ] All PNGs MUST have a transparent background
- [ ] All PNGs MUST be 32-bit RGBA
- [ ] Scaled variants (`*.scale-200.png` etc.) are RECOMMENDED for crisp display

---

## 4. Network Security

ALL external network calls MUST use HTTPS. No hardcoded `http://` URLs are permitted.

Files to audit:
- [ ] `api.go` — OpenAI API calls
- [ ] `update.go` — GitHub Releases API, download URLs
- [ ] `llm_download.go` — LLM model downloads
- [ ] `llm.go` — local LLM server communication (localhost is exempt)
- [ ] `internal/models/` — STT model download URLs
- [ ] `notification.go` — any URLs opened by notifications

Verification method:
```powershell
# Search for hardcoded http:// URLs (excluding localhost and comments)
rg 'http://' --glob '*.go' --glob '!*_test.go' | findstr /V "localhost" | findstr /V "127.0.0.1" | findstr /V "//"
```

---

## 5. Auto-Update Behavior

- [ ] `isStorePackage()` in `update.go` MUST gate **all** self-update logic
- [ ] MSIX apps MUST NOT trigger exe-replacement updates (Store handles updates)
- [ ] MSIX apps MUST NOT show "update available" notifications for app updates
- [ ] Local LLM / STT model downloads are **still allowed** in MSIX — these are user-initiated data downloads, not app updates
- [ ] The update check interval and UI elements MUST be hidden or disabled when `isStorePackage()` returns `true`

---

## 6. Content & Quality

- [ ] App MUST NOT crash on launch (test with a clean `%APPDATA%\Whispaste` directory)
- [ ] App MUST handle missing API key gracefully (show settings, not crash)
- [ ] No offensive or inappropriate content in UI, icons, or sounds
- [ ] IARC content rating: suitable for all ages (no violence, no user-generated content sharing)
- [ ] App description in Store listing MUST accurately match actual functionality
- [ ] All UI strings MUST be free of placeholder text or debug artifacts

---

## 7. Deployment Channels Checklist

For **every release**, verify all channels are complete:

### NSIS Installer
- [ ] `installer/whispaste.nsi` builds without errors
- [ ] Installer includes the main exe + all required DLLs (`sherpa-onnx-c-api.dll`, `sherpa-onnx-cxx-api.dll`, `onnxruntime.dll`)
- [ ] Uninstaller removes all installed files and registry entries

### Portable Distribution
- [ ] Portable ZIP contains: `whispaste.exe` + 3 DLLs
- [ ] Runs from any directory without installation

### MSIX Package
- [ ] `msix/AppxManifest.xml` passes all checks from Section 1
- [ ] MSIX builds and signs without errors
- [ ] Package installs and launches on a clean Windows 10 1809+ system

### Release Workflow
- [ ] `.github/workflows/release.yml` runs successfully on tag push
- [ ] SHA256 checksums are generated for **all** release artifacts
- [ ] Version strings updated in all 3 manual locations before tagging:
  - `types.go` — `var AppVersion`
  - `winres/winres.json` — `file_version` + `product_version`
  - `ui_main/template.html` — `about-version` fallback text
- [ ] Release notes accurately describe changes since the last release

---

## 8. Store Listing (Partner Center)

- [ ] **Localized name** — provided in EN and DE
- [ ] **Localized description** — includes feature highlights, provided in EN and DE
- [ ] **Screenshots** — at least 1 per language (1366×768 recommended)
- [ ] **Category** — set to **Productivity**
- [ ] **System requirements** — documented: Windows 10 1809+, microphone required
- [ ] **Age rating** — IARC questionnaire completed (expected: 3+ / Everyone)
- [ ] **Privacy policy URL** — set in listing (see Section 2)
- [ ] **Support contact** — email or URL provided
- [ ] **Copyright / Trademark** — no infringement in name, icon, or description

---

## 📤 Output Format

When this skill is invoked, produce a report in this format:

```
## 🏪 Store Compliance Report
**Date:** [Date]
**Scope:** [Release version or changed files]
**Result:** ✅ Compliant | ⚠️ Partially Compliant | ❌ Non-Compliant

### Section Results
| # | Section | Status | Issues |
|---|---------|--------|--------|
| 1 | MSIX Manifest | ✅/⚠️/❌ | [count] |
| 2 | Privacy Policy | ✅/⚠️/❌ | [count] |
| 3 | Logo Assets | ✅/⚠️/❌ | [count] |
| 4 | Network Security | ✅/⚠️/❌ | [count] |
| 5 | Auto-Update | ✅/⚠️/❌ | [count] |
| 6 | Content & Quality | ✅/⚠️/❌ | [count] |
| 7 | Deployment Channels | ✅/⚠️/❌ | [count] |
| 8 | Store Listing | ✅/⚠️/❌ | [count] |

### Findings
[List each issue with section number, severity, and remediation]

### Next Steps
[Concrete actions required before submission]
```

**Severity levels:**
- 🔴 **BLOCKER** — Store will reject. MUST fix before submission.
- 🟡 **WARNING** — May cause rejection or poor review. SHOULD fix.
- 🔵 **INFO** — Best practice recommendation. MAY fix.

---

## 🚫 Absolute Rules

1. **NEVER** submit to the Store with an `http://` URL in production code
2. **NEVER** allow self-update logic to execute inside an MSIX package
3. **NEVER** ship without a publicly accessible privacy policy
4. **NEVER** use version format other than `X.Y.Z.0` in the MSIX manifest
5. **NEVER** reference logo assets in the manifest that don't exist on disk
6. **NEVER** skip this check because "it's just a patch release"
