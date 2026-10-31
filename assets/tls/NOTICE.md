# mozilla-cacert.pem — bundled Mozilla root CA store (Windows TLS)

Mozilla's CA certificate bundle, as published by the curl project, copied
unchanged.

- **Source:** https://curl.se/ca/cacert.pem (derived from Mozilla's NSS root store)
- **Version:** "Certificate data from Mozilla as of: Tue Oct 20 13:32:40 2026 GMT" (in the file header)
- **Certificates:** 118
- **SHA-256:** `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`
- **License:** MPL-2.0 (Mozilla Public License 2.0). The file is used unmodified.

## Why it is bundled

A fresh Windows install only holds a small set of root certificates. Other
roots are fetched by Windows on demand, when Schannel (Edge, PowerShell)
builds a chain. Dart's TLS stack reads the Windows store but never triggers
that fetch. Without the bundle, downloads from huggingface.co (chain: Amazon
RSA 2048 M01 → Amazon Root CA 1 → Starfield Services Root CA G2) fail with
`CERTIFICATE_VERIFY_FAILED`.

At app start on Windows, `lib/core/tls/mozilla_roots_loader.dart` adds these
certificates to `SecurityContext.defaultContext`. The system store stays
active, so company proxy and antivirus roots still apply.

## Update before each release

`scripts/update-mozilla-cacert.sh` downloads the file, checks its SHA-256
against curl.se, requires the roots above, and records the new version here.
Guard test: `test/core/tls/mozilla_roots_asset_test.dart`.
