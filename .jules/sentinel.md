## 2026-08-08 - [Sentinel] Prevent Command Injection in macOS Update Script
**Vulnerability:** The `MacUpdateInstaller` embedded dynamic inputs (like the DMG path) directly into a generated shell script using fragile manual quoting (`_shq`), which is susceptible to command injection if quotes can be bypassed.
**Learning:** Shell script generation via string interpolation is an anti-pattern. Even with manual escaping, it is difficult to secure perfectly and introduces a wide attack surface for malicious payloads.
**Prevention:** Always parameterize shell commands. Use positional arguments (``, ``) in scripts and pass dynamic values via the native process arguments array (`Process.start`), which hands them directly to the OS without shell parsing.
