/// Centralized app metadata — single source of truth for version and identity.
///
/// [appVersion] is read at runtime from the platform package metadata
/// (Info.plist on macOS, resource block on Windows, AndroidManifest on Android).
/// Flutter populates those from `pubspec.yaml` at build time, so the only
/// source of truth for the version is `pubspec.yaml` — no manual mirror.
///
/// Call [initAppInfo] once during bootstrap (after
/// `WidgetsFlutterBinding.ensureInitialized()`) before reading [appVersion].
library;

import 'package:package_info_plus/package_info_plus.dart';

/// App name for display.
const appName = 'WhisPaste';

String _appVersion = 'unknown';

/// Current app version (X.Y.Z). `'unknown'` until [initAppInfo] resolves.
String get appVersion => _appVersion;

/// User-Agent header value for HTTP requests.
String get appUserAgent => '$appName/$_appVersion';

// ──────────────────────────────────────────────────────────────
// Sentry Release Metadata
// ──────────────────────────────────────────────────────────────

/// Sentry release identifier. Format: `whispaste@{version}`
/// Used in app_monitoring.dart for release tracking.
String get sentryRelease => '$appName@$_appVersion';

/// Sentry organization slug. Used in CI/CD workflows.
const sentryOrg = 'silvio-lindstedt-und-maik-g-y2';

/// Sentry project slug. Used in CI/CD workflows.
const sentryProject = 'flutter_whispaste';

/// Sentry instance region.
const sentryRegion = 'de';

// ──────────────────────────────────────────────────────────────
// Bootstrap
// ──────────────────────────────────────────────────────────────

/// Populates [appVersion] from the platform package metadata.
///
/// Call once during app bootstrap after
/// `WidgetsFlutterBinding.ensureInitialized()`. Safe to call multiple times.
Future<void> initAppInfo() async {
  final info = await PackageInfo.fromPlatform();
  _appVersion = info.version;
}
