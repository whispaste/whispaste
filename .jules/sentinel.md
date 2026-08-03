## 2024-05-24 - Sentry Breadcrumbs Leak Secrets
**Vulnerability:** Sentry breadcrumbs from log statements could contain sensitive information (like API keys) and leak them to crash reports.
**Learning:** `AppLogger` is the source of breadcrumbs, and `event.breadcrumbs` was not being scrubbed in Sentry `beforeSend`, even though `event.message` and `event.exceptions` were.
**Prevention:** In `CrashReporter.beforeSend`, always apply the `containsSensitiveData` checker not just to the primary message/exception, but also to `event.breadcrumbs`. Return `null` to drop the crash report entirely if any part of it is tainted.
