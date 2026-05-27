/// Centralized app metadata — single source of truth for version and identity.
///
/// The version flows from `pubspec.yaml`. It reaches the running app via two
/// channels, in order of precedence:
///
///   1. **Compile-time `--dart-define=APP_VERSION=…`** — CI release builds
///      pass the resolved tag/pubspec version into the build. This makes
///      [appVersion] available *synchronously* at app start, so Sentry's
///      `options.release` is correct from the very first captured event.
///
///   2. **Runtime [PackageInfo.fromPlatform]** — local dev (`flutter run`)
///      reads the version from the platform package metadata (Info.plist on
///      macOS, resource block on Windows, AndroidManifest on Android), which
///      Flutter populates from `pubspec.yaml` at build time. Resolved a few
///      ms after `WidgetsFlutterBinding.ensureInitialized()` via [initAppInfo].
///
/// No manual mirror — `pubspec.yaml` is the only edit site for a version bump.
library;

import 'dart:ffi' show Abi;

import 'package:package_info_plus/package_info_plus.dart';

/// App name for display.
const appName = 'WhisPaste';

/// Compile-time version baked in by CI release builds via
/// `--dart-define=APP_VERSION=<version>`. Empty string when absent (local dev).
const _compileTimeVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '',
);

String _runtimeAppVersion = 'unknown';

/// Current app version (X.Y.Z).
///
/// Returns the compile-time value when present (CI release builds), otherwise
/// the runtime value populated by [initAppInfo]. Falls back to `'unknown'`
/// during the brief window before [initAppInfo] resolves on dev builds.
String get appVersion =>
    _compileTimeVersion.isNotEmpty ? _compileTimeVersion : _runtimeAppVersion;

/// User-Agent header value for HTTP requests.
String get appUserAgent => '$appName/$appVersion';

// ──────────────────────────────────────────────────────────────
// Sentry Release Metadata
// ──────────────────────────────────────────────────────────────

/// Sentry release identifier. Format: `whispaste@{version}`.
/// Used in app_monitoring.dart for release tracking and must match the
/// `whispaste@$version` tag the release workflow uploads symbols against.
String get sentryRelease => '$appName@$appVersion';

/// Sentry organization slug. Used in CI/CD workflows.
const sentryOrg = 'silvio-lindstedt-und-maik-g-y2';

/// Sentry project slug. Used in CI/CD workflows.
const sentryProject = 'flutter_whispaste';

/// Sentry instance region.
const sentryRegion = 'de';

/// Process architecture tag for Sentry's `dist` field and `arch` scope tag.
///
/// Replaces the previous `0x7FFFFFFFFFFFFFFF > 0` compile-time hack that
/// hard-coded `'x64'` on every platform — and silently mislabelled every
/// Apple-Silicon (ARM64) crash as x64. The real architecture matters for
/// hardware-cluster filters in Sentry, especially after the Apple-Silicon
/// transition where the same crash on arm64 and x64 have completely
/// different native stacks.
///
/// Returns a compact label (`arm64`, `x64`, `x86`, `arm`, `riscv64`,
/// `riscv32`) for the common cases and falls back to the raw `Abi`
/// enum name (lowercased) for anything `dart:ffi` introduces later, so
/// new architectures are visible in Sentry without a code change here.
String currentArchTag() {
  final raw = Abi.current().toString().split('.').last.toLowerCase();
  if (raw.contains('arm64')) return 'arm64';
  if (raw.contains('x64')) return 'x64';
  if (raw.contains('ia32') || raw.endsWith('x86')) return 'x86';
  if (raw.contains('riscv64')) return 'riscv64';
  if (raw.contains('riscv32')) return 'riscv32';
  if (raw.contains('arm')) return 'arm';
  return raw;
}

// ──────────────────────────────────────────────────────────────
// Bootstrap
// ──────────────────────────────────────────────────────────────

/// Populates the runtime fallback for [appVersion] from
/// [PackageInfo.fromPlatform]. No-op when the compile-time `APP_VERSION`
/// was injected by CI. Call once after
/// `WidgetsFlutterBinding.ensureInitialized()`.
Future<void> initAppInfo() async {
  if (_compileTimeVersion.isNotEmpty) return;
  final info = await PackageInfo.fromPlatform();
  _runtimeAppVersion = info.version;
}
