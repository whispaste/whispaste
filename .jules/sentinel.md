## 2026-08-08 - [Sentinel] Prevent Command Injection in macOS Update Script
**Vulnerability:** The `MacUpdateInstaller` embedded dynamic inputs (like the DMG path) directly into a generated shell script using fragile manual quoting (`_shq`), which is susceptible to command injection if quotes can be bypassed.
**Learning:** Shell script generation via string interpolation is an anti-pattern. Even with manual escaping, it is difficult to secure perfectly and introduces a wide attack surface for malicious payloads.
**Prevention:** Always parameterize shell commands. Use positional arguments (``, ``) in scripts and pass dynamic values via the native process arguments array (`Process.start`), which hands them directly to the OS without shell parsing.

## 2024-05-18 - Prevent Command Injection via heredoc expansion in macOS Update Script
**Vulnerability:** The macOS update script generated an inner script using an unquoted heredoc (`<<WPINNER`), causing the shell to expand variables like `$STAGE` before the inner script ran. This exposed the execution path to command injection, particularly concerning as the script runs with `osascript` administrator privileges, leading to potential Local Privilege Escalation (LPE).
**Learning:** Even when external variables are passed correctly to an outer script, if that script generates another script via heredoc, the heredoc delimiter must be quoted (`<<'EOF'`) to prevent premature variable expansion.
**Prevention:** Always quote heredoc delimiters when generating scripts. Pass required dynamic data to the generated script via positional arguments, and when using `osascript`, handle those arguments via `on run argv` and AppleScript's `quoted form of` command to ensure safe parameterization.
## 2025-02-28 - Windows command injection via `cmd /c start`
**Vulnerability:** Command injection when opening Windows URLs (such as `mailto:`) using `Process.run('cmd', ['/c', 'start', '', url])` in Dart.
**Learning:** `cmd.exe`'s complex parsing rules can evaluate special shell characters like `&` in unsanitized URLs even if they are passed correctly as arguments in `CreateProcess` via Dart's `Process.run`. Using `cmd` to open external resources exposes the app to unintended command execution.
**Prevention:** Avoid `cmd.exe`. Always use `explorer` directly (e.g., `Process.run('explorer', [url])`) to safely open URLs and files on Windows without going through a command interpreter.
## 2025-02-28 - Flaky CI vs Security Check
**Vulnerability:** Flaky CI tests due to upstream failures in `npm audit` should not be bypassed by setting `continue-on-error: true`.
**Learning:** Even if `npm audit` is throwing 503 errors due to upstream infrastructure unreliability, bypassing it introduces a severe security regression because actual high severity vulnerabilities will no longer fail the build. A security PR must not silence security gates.
**Prevention:** If an upstream service like `npm audit` is failing intermittently, do not modify the CI script to ignore errors. Retry the CI job or wait for the upstream service to recover.
