# WinSparkle 0.9.3 — Provenance

Prebuilt WinSparkle binaries, vendored because the `auto_updater_windows` package
(stuck at 1.0.0) bundles WinSparkle 0.8.1, which is DSA-only and **cannot verify
EdDSA signatures**. WinSparkle 0.9.0+ added EdDSA (Ed25519) — the same signature
scheme macOS Sparkle uses — so the WhisPaste self-update chain stays unified on
EdDSA across both desktop platforms.

## Source

- Upstream: <https://github.com/vslavik/winsparkle>
- Release: `v0.9.3` (2026-05-18)
- Asset: `WinSparkle-0.9.3.zip`
- Download: <https://github.com/vslavik/winsparkle/releases/download/v0.9.3/WinSparkle-0.9.3.zip>
- License: MIT (`COPYING`)

Only `*.dll` + `*.lib` + `include/` are committed (PDBs and `bin/` tools omitted).
To re-verify, download the asset and compare the SHA-256 digests below.

## SHA-256 (this checkout)

| File | SHA-256 |
|---|---|
| `x64/Release/WinSparkle.dll` | `a69acfcbcb2af0eb4c3a27511401bac56a157e6663c4b48d488ef2b659fc8b37` |
| `x64/Release/WinSparkle.lib` | `9b0b326fe09ec828e5f11aba8a61f58562ad7d1413efd0b0783bb275e57b0649` |
| `ARM64/Release/WinSparkle.dll` | `b4d26476fab5701d0993e375af643a914689629e285eef7ab965a2f87bfb326f` |
| `Release/WinSparkle.dll` (x86) | `d1e2f217c4f60f20c460ba2921f8872fd1740fe3ef3f344f7f9ac4104a5b3e40` |

## Upgrade notes

- EdDSA public key is wired in `../auto_updater.cpp` via
  `win_sparkle_set_eddsa_public_key()` (called before `win_sparkle_init()`).
- DSA (`win_sparkle_set_dsa_pub_pem`) is deprecated as of 0.9.0 and ignored once
  the EdDSA key is set; do not re-introduce DSA.
