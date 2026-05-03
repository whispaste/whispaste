/// Centralized app metadata — single source of truth for version and identity.
///
/// Keep in sync with `pubspec.yaml` `version:` field.
/// Bump here AND in pubspec.yaml when releasing a new version.
library;

/// App version string (semver). Must match pubspec.yaml.
const appVersion = '1.2.12';

/// App name for display.
const appName = 'WhisPaste';

/// User-Agent header value for HTTP requests.
const appUserAgent = '$appName/$appVersion';

// ──────────────────────────────────────────────────────────────
// Sentry Release Metadata
// ──────────────────────────────────────────────────────────────

/// Sentry release identifier. Format: `whispaste@{version}`
/// Used in app_monitoring.dart for release tracking.
const sentryRelease = '$appName@$appVersion';

/// Sentry organization slug. Used in CI/CD workflows.
const sentryOrg = 'silvio-lindstedt-und-maik-g-y2';

/// Sentry project slug. Used in CI/CD workflows.
const sentryProject = 'flutter_whispaste';

/// Sentry instance region.
const sentryRegion = 'de';
