/// Centralized app metadata — single source of truth for version and identity.
///
/// Keep in sync with `pubspec.yaml` `version:` field.
/// Bump here AND in pubspec.yaml when releasing a new version.
library;

/// App version string (semver). Must match pubspec.yaml.
const appVersion = '1.2.0';

/// App name for display.
const appName = 'WhisPaste';

/// User-Agent header value for HTTP requests.
const appUserAgent = '$appName/$appVersion';
