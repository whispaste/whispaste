# WhisPaste — Microsoft Store Submission Guide

> Step-by-step instructions for publishing WhisPaste to the Microsoft Store.
> Last updated: 2026-03-09

---

## Prerequisites Checklist

Before starting, ensure you have:

- [x] App builds successfully (`go build` + `release.yml` CI green)
- [x] MSIX manifest configured (`msix/AppxManifest.xml`)
- [x] All 27 logo PNGs generated (`msix/Assets/`)
- [x] Privacy policy published (EN: `/privacy/`, DE: `/datenschutz/`)
- [x] Auto-update gated for MSIX (`isStorePackage()` in `update.go`)
- [x] Store listing metadata prepared (EN/DE descriptions, features)
- [ ] **Microsoft Partner Center account** (see Step 1)
- [ ] **Stable version number** (e.g., `1.0.0`, not `0.4.0-alpha`)
- [ ] **Screenshots** (see Step 6.7)

---

## Step 1: Register for Microsoft Partner Center

1. Go to https://partner.microsoft.com/dashboard
2. Sign in with your Microsoft account (or create one)
3. Enroll as an **Individual developer** (one-time fee: ~19 USD / ~14 EUR)
4. Complete identity verification (takes 1-3 business days)
5. Once approved, you'll see the **Apps and Games** section in your dashboard

> **Note:** The Publisher identity in `AppxManifest.xml` must match your Partner Center registration.
> Current: `CN=SilvioLindstedt` — update if Partner Center assigns a different publisher ID.

---

## Step 2: Reserve Your App Name

1. In Partner Center → **Apps and Games** → **New product** → **MSIX or PWA app**
2. Reserve the name **"WhisPaste"**
3. If taken, try **"WhisPaste - Voice to Text"**
4. Note the **Package/Identity/Name** and **Package/Identity/Publisher** values — these must match `AppxManifest.xml`

### Update AppxManifest.xml

After reserving, Partner Center shows your exact Identity values. Update `msix/AppxManifest.xml`:

```xml
<Identity Name="XXXXX.WhisPaste"
          Publisher="CN=XXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
          Version="1.0.0.0"
          ProcessorArchitecture="x64" />
```

The `Publisher` must exactly match the certificate from Partner Center (usually a GUID format).

---

## Step 3: Code-Signing

### For Store submission (recommended)
**You don't need to sign the MSIX yourself.** The Microsoft Store signs it automatically during certification. Just upload the unsigned MSIX.

### For sideloading / testing (optional)
```powershell
# Create a test certificate (PowerShell as Admin)
New-SelfSignedCertificate -Type Custom -Subject "CN=SilvioLindstedt" `
    -KeyUsage DigitalSignature -FriendlyName "WhisPaste Test" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

# Sign the MSIX
& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe" `
    sign /fd SHA256 /a /f whispaste-test.pfx /p YourPassword whispaste.msix
```

---

## Step 4: Prepare a Stable Release Version

The Microsoft Store **does not accept pre-release versions** (no `-alpha`, `-beta`, `-rc` suffixes). The version must be strictly `X.Y.Z.0` (four numeric parts).

### Bump to 1.0.0

Update these 5 locations (see `.agents/skills/versioning/SKILL.md`):

1. **`types.go`** — `var AppVersion = "1.0.0"`
2. **`winres/winres.json`** — `file_version: "1.0.0.0"` + `product_version: "1.0.0"`
3. **`winres/winres.json`** (StringFileInfo) — `FileVersion: "1.0.0"` + `ProductVersion: "1.0.0"`
4. **`ui_main/pages/06-about.html`** — `v1.0.0`

### Tag and push

```powershell
git tag -a v1.0.0 -m "v1.0.0: First stable release"
git push origin v1.0.0
```

The `release.yml` workflow automatically builds the MSIX with the correct version injected.

---

## Step 5: Download the MSIX from GitHub Releases

After the release workflow completes:

1. Go to https://github.com/whispaste/whispaste/releases/tag/v1.0.0
2. Download `whispaste.msix`
3. Optional: test locally before submitting

```powershell
# Enable developer mode in Windows Settings first, then:
Add-AppxPackage -Path whispaste.msix
```

---

## Step 6: Submit to Partner Center

### 6.1 Create a new submission

Partner Center → Your app → **Start your submission**

### 6.2 Pricing and availability

- **Price:** Free
- **Markets:** All markets (or select specific ones)
- **Visibility:** Public
- **Schedule:** Publish as soon as certified

### 6.3 Properties

- **Category:** Productivity
- **Subcategory:** General
- **Privacy policy URL:** `https://whispaste.github.io/whispaste/privacy/`
- **Support contact:** Your email or GitHub Issues URL
- **Website:** `https://whispaste.github.io/whispaste/`

### 6.4 Age ratings

- Complete the IARC questionnaire
- Expected rating: **3+ / Everyone** (productivity tool, no user-generated content sharing)

### 6.5 Packages

1. Upload `whispaste.msix`
2. Partner Center validates the package structure automatically
3. Fix any validation errors before proceeding

### 6.6 Store listing

Use the prepared metadata from `STORE-LISTING.md`:

**English (en-US):**
- **App name:** WhisPaste
- **Short description:** Voice to text, pasted anywhere. Fast speech transcription for Windows.
- **Description:** (copy from STORE-LISTING.md §3 English)
- **Features:** (copy 7 feature bullets from STORE-LISTING.md §4 English)

**German (de-DE):**
- **App name:** WhisPaste
- **Short description:** Sprache zu Text, überall eingefügt. Schnelle Spracherkennung für Windows.
- **Description:** (copy from STORE-LISTING.md §3 Deutsch)
- **Features:** (copy 7 feature bullets from STORE-LISTING.md §4 Deutsch)

### 6.7 Screenshots

Minimum 1 screenshot per language. Recommended: **1366×768** or **1920×1080** (PNG).

Suggested screenshots:
1. **Settings dashboard** — shows the main UI with AI & Models section
2. **Recording overlay** — the always-on-top overlay with waveform
3. **History view** — search results with tags and projects
4. **Smart Mode** — preset selection with AI post-processing

### 6.8 Submit for certification

1. Review all sections → all green checkmarks
2. Click **Submit to the Store**
3. Certification: **1-3 business days**
4. Email notification on approval or rejection

---

## Step 7: Post-Submission

### If approved ✅
- App is live on the Microsoft Store
- Share the Store link
- Future updates: bump version → tag → release → new submission with updated MSIX

### If rejected ❌

| Common Reason | Fix |
|---------------|-----|
| App crashes on launch | Test on clean Windows 10 1809 VM |
| Missing privacy policy | Verify URL is accessible |
| Package identity mismatch | Update `AppxManifest.xml` Identity to match Partner Center |
| Misleading description | Ensure description matches actual features |

---

## What's Ready vs. What You Need To Do

| Item | Status | Your Action |
|------|--------|-------------|
| App code & features | ✅ Done | — |
| MSIX manifest | ✅ Done | Update Identity after Partner Center registration |
| Logo assets (27 PNGs) | ✅ Done | — |
| Privacy policy (EN/DE) | ✅ Done | — |
| Auto-update MSIX gate | ✅ Done | — |
| Store listing text (EN/DE) | ✅ Done | Copy into Partner Center |
| Network security (HTTPS) | ✅ Done | — |
| Partner Center account | 🔲 Manual | Register + ~19 USD fee |
| Stable version (1.0.0) | 🔲 Manual | Bump version in 5 locations, tag, push |
| Screenshots (3-4) | 🔲 Manual | Take screenshots of the running app |
| IARC age rating | 🔲 Manual | Complete questionnaire in Partner Center |

---

## Useful Links

- [Partner Center Dashboard](https://partner.microsoft.com/dashboard)
- [Store Policies](https://learn.microsoft.com/windows/uwp/publish/store-policies)
- [MSIX Packaging](https://learn.microsoft.com/windows/msix/)
- [App Certification Process](https://learn.microsoft.com/windows/uwp/publish/the-app-certification-process)
- [Store Listing Metadata](../STORE-LISTING.md) (session file)
- [Privacy Policy EN](https://whispaste.github.io/whispaste/privacy/)
- [Privacy Policy DE](https://whispaste.github.io/whispaste/datenschutz/)
