/// Deploy channel detection — determines how WhisPaste was installed.
///
/// Four channels exist:
/// - **store**: Installed from an OS store — MS Store on Windows (MSIX
///   package identity detected) or the Mac App Store on macOS (MAS build,
///   see [kIsMasBuild])
/// - **packageManaged**: Installed via a third-party package manager that
///   owns its own upgrade flow — Homebrew Cask (macOS), Scoop (Windows),
///   Snap or Flatpak (Linux). See [isExternallyManaged].
/// - **installer**: Installed via NSIS Setup.exe (registry marker present,
///   Windows only)
/// - **portable**: Running from extracted ZIP/AppImage, a direct-download
///   macOS build, a `.deb` install, or a dev environment (fallback)
///
/// The channel determines update behavior:
/// - Store / package-managed → updates owned by the store/package manager,
///   the in-app self-updater must stay silent (see [isExternallyManaged])
/// - Installer → check GitHub Releases, download & launch new Setup.exe
/// - Portable → check GitHub Releases, show notification with download link
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/build_config.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('DeployChannel');

/// How the app was deployed to this machine.
enum DeployChannel {
  /// Installed from Microsoft Store or other OS store (MSIX/AppX package).
  store,

  /// Installed via a third-party package manager that owns its own upgrade
  /// flow: Homebrew Cask (macOS), Scoop (Windows), Snap or Flatpak (Linux).
  packageManaged,

  /// Installed via NSIS installer (WhisPaste-Setup.exe from GitHub).
  installer,

  /// Running from extracted ZIP/AppImage, a direct-download macOS build, a
  /// `.deb` install, or a dev environment (fallback).
  portable,
}

/// Whether [channel] is managed by an external updater — an OS store or a
/// system package manager. The in-app self-updater (Sparkle/WinSparkle, the
/// GitHub-Releases check) must stay off for these: running it anyway would
/// fight the manager that already owns upgrades for this install (e.g.
/// Sparkle overwriting a Homebrew-managed `.app`, or a GitHub-check nagging
/// a Snap/Flatpak user whose store already auto-updates them).
bool isExternallyManaged(DeployChannel channel) =>
    channel == DeployChannel.store || channel == DeployChannel.packageManaged;

/// Override for testing. When non-null, [detectDeployChannel] returns this
/// instead of probing the OS.
@visibleForTesting
DeployChannel? deployChannelOverride;

/// Detects the deploy channel once.
///
/// Detection order (Windows):
/// 1. MSIX package identity → [DeployChannel.store]
/// 2. Scoop install path (`…\scoop\apps\whispaste\…`) → [DeployChannel.packageManaged]
/// 3. Registry marker `HKCU\Software\WhisPaste\InstallSource` → [DeployChannel.installer]
/// 4. Fallback → [DeployChannel.portable]
///
/// macOS: [kIsMasBuild] is a compile-time constant that is `true` only for
/// binaries built against the Xcode "MAS" configuration (App Sandbox +
/// `AppStore.entitlements`) — the same build variant this repo ships to the
/// Mac App Store, so it doubles as a reliable store-channel signal without
/// needing a runtime App Store receipt check. Non-MAS macOS builds check for
/// a Homebrew Caskroom entry (`_hasHomebrewCaskEntry`) next, then fall back
/// to [DeployChannel.portable] (direct DMG download).
///
/// Linux: [_detectLinuxChannel] recognizes Snap and Flatpak (both
/// package-managed) via their well-known runtime environment markers, and
/// AppImage via `$APPIMAGE` (stays [DeployChannel.portable] — no repo
/// auto-updates it). Everything else (`.deb`, tarball, dev run) also falls
/// back to [DeployChannel.portable].
DeployChannel detectDeployChannel() {
  if (deployChannelOverride != null) return deployChannelOverride!;
  if (Platform.isMacOS) {
    if (kIsMasBuild) {
      _log.info('Deploy channel: store (MAS build)');
      return DeployChannel.store;
    }
    if (_hasHomebrewCaskEntry()) {
      _log.info('Deploy channel: packageManaged (Homebrew Caskroom entry)');
      return DeployChannel.packageManaged;
    }
    _log.info('Deploy channel: portable (non-MAS macOS build)');
    return DeployChannel.portable;
  }
  if (Platform.isLinux) {
    final linuxChannel = _detectLinuxChannel();
    _log.info('Deploy channel: $linuxChannel (Linux)');
    return linuxChannel;
  }
  if (!Platform.isWindows) return DeployChannel.portable;

  // 1. Check for MSIX package identity via GetCurrentPackageFullName.
  if (_hasMsixPackageIdentity()) {
    _log.info('Deploy channel: store (MSIX package identity detected)');
    return DeployChannel.store;
  }

  // 2. Check for a Scoop install path.
  if (isScoopExecutablePath(Platform.resolvedExecutable)) {
    _log.info('Deploy channel: packageManaged (Scoop install path)');
    return DeployChannel.packageManaged;
  }

  // 3. Check for NSIS installer registry marker.
  if (_hasInstallerRegistryMarker()) {
    _log.info('Deploy channel: installer (registry marker found)');
    return DeployChannel.installer;
  }

  // 4. Fallback.
  _log.info(
    'Deploy channel: portable (no store/package-manager/installer marker)',
  );
  return DeployChannel.portable;
}

// ---------------------------------------------------------------------------
// Linux: Snap / Flatpak / AppImage detection
// ---------------------------------------------------------------------------

/// Pure decision: which [DeployChannel] does this Linux runtime environment
/// indicate? Injectable [env] + [flatpakInfoExists] so this is unit-testable
/// without a real Linux runtime.
///
/// - Snap sets `SNAP`/`SNAP_NAME` for every running snap.
/// - Flatpak sandboxes expose `/.flatpak-info`; `FLATPAK_ID` is also commonly
///   set by the Flatpak runtime.
/// - AppImage sets `APPIMAGE` to the mounted image path. No repository
///   tracks/auto-updates it, so it stays [DeployChannel.portable] like a
///   plain extracted tarball — recognized explicitly so future
///   diagnostics/telemetry can tell it apart, without changing update
///   behavior today.
@visibleForTesting
DeployChannel linuxChannelFromEnv(
  Map<String, String> env, {
  required bool flatpakInfoExists,
}) {
  if (env.containsKey('SNAP') || env.containsKey('SNAP_NAME')) {
    return DeployChannel.packageManaged;
  }
  if (flatpakInfoExists || env.containsKey('FLATPAK_ID')) {
    return DeployChannel.packageManaged;
  }
  if (env.containsKey('APPIMAGE')) return DeployChannel.portable;
  return DeployChannel.portable;
}

DeployChannel _detectLinuxChannel() => linuxChannelFromEnv(
  Platform.environment,
  flatpakInfoExists: File('/.flatpak-info').existsSync(),
);

// ---------------------------------------------------------------------------
// macOS: Homebrew Cask detection
// ---------------------------------------------------------------------------

/// Best-effort Homebrew Cask detection. `brew install --cask` moves the
/// `.app` bundle straight into `/Applications` — unlike CLI binaries,
/// Homebrew does not symlink app bundles, so the installed app is on-disk
/// indistinguishable by path from a manual DMG install. The Caskroom
/// directory it leaves behind is the cheapest reliable signal without
/// shelling out to `brew` itself (slow, and not guaranteed on PATH for a
/// GUI-launched app).
@visibleForTesting
bool hasHomebrewCaskEntry({
  bool Function(String path) dirExists = _defaultDirExists,
}) {
  const prefixes = ['/opt/homebrew', '/usr/local'];
  for (final prefix in prefixes) {
    if (dirExists('$prefix/Caskroom/whispaste')) return true;
  }
  return false;
}

bool _defaultDirExists(String path) => Directory(path).existsSync();

bool _hasHomebrewCaskEntry() => hasHomebrewCaskEntry();

// ---------------------------------------------------------------------------
// Windows: Scoop detection
// ---------------------------------------------------------------------------

/// Pure decision: does [exePath] point at a Scoop-managed install? Scoop
/// installs apps under `…\scoop\apps\whispaste\<version-or-current>\…`
/// (per-user) or `…\scoop\apps\whispaste\…` under the global Scoop root —
/// both share the `\apps\whispaste\` path segment this checks for.
@visibleForTesting
bool isScoopExecutablePath(String exePath) {
  final normalized = exePath.replaceAll('/', r'\').toLowerCase();
  return normalized.contains(r'\scoop\apps\whispaste\');
}

// ---------------------------------------------------------------------------
// MSIX detection via GetCurrentPackageFullName (kernel32.dll)
// ---------------------------------------------------------------------------

// Win32 constants.
const _errorSuccess = 0;

/// `GetCurrentPackageFullName` returns `ERROR_SUCCESS` (0) when the process
/// runs inside an MSIX/AppX package, or `APPMODEL_ERROR_NO_PACKAGE` (15700).
bool _hasMsixPackageIdentity() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentPackageFullName = kernel32
        .lookupFunction<
          Int32 Function(Pointer<Uint32> length, Pointer<Uint16> fullName),
          int Function(Pointer<Uint32> length, Pointer<Uint16> fullName)
        >('GetCurrentPackageFullName');

    final length = calloc<Uint32>();
    final nameBuffer = calloc<Uint16>(256);
    length.value = 256;

    try {
      final result = getCurrentPackageFullName(length, nameBuffer);
      return result == _errorSuccess;
    } finally {
      calloc.free(length);
      calloc.free(nameBuffer);
    }
  } catch (e) {
    _log.debug('MSIX detection failed (expected on non-MSIX): $e');
    return false;
  }
}

// ---------------------------------------------------------------------------
// NSIS installer detection via registry (pure FFI — no external package)
// ---------------------------------------------------------------------------

// Win32 registry constants.
const _hkeyCurrentUser = 0x80000001;
const _keyRead = 0x20019; // KEY_READ
const _regSz = 1; // REG_SZ

// advapi32.dll function signatures.
typedef _RegOpenKeyExNative =
    Int32 Function(
      IntPtr hKey,
      Pointer<Utf16> lpSubKey,
      Uint32 ulOptions,
      Uint32 samDesired,
      Pointer<IntPtr> phkResult,
    );
typedef _RegOpenKeyExDart =
    int Function(
      int hKey,
      Pointer<Utf16> lpSubKey,
      int ulOptions,
      int samDesired,
      Pointer<IntPtr> phkResult,
    );

typedef _RegQueryValueExNative =
    Int32 Function(
      IntPtr hKey,
      Pointer<Utf16> lpValueName,
      Pointer<Uint32> lpReserved,
      Pointer<Uint32> lpType,
      Pointer<Uint8> lpData,
      Pointer<Uint32> lpcbData,
    );
typedef _RegQueryValueExDart =
    int Function(
      int hKey,
      Pointer<Utf16> lpValueName,
      Pointer<Uint32> lpReserved,
      Pointer<Uint32> lpType,
      Pointer<Uint8> lpData,
      Pointer<Uint32> lpcbData,
    );

typedef _RegCloseKeyNative = Int32 Function(IntPtr hKey);
typedef _RegCloseKeyDart = int Function(int hKey);

/// The NSIS installer writes `InstallSource=installer` to the registry.
bool _hasInstallerRegistryMarker() {
  try {
    final advapi32 = DynamicLibrary.open('advapi32.dll');

    final regOpenKeyEx = advapi32
        .lookupFunction<_RegOpenKeyExNative, _RegOpenKeyExDart>(
          'RegOpenKeyExW',
        );
    final regQueryValueEx = advapi32
        .lookupFunction<_RegQueryValueExNative, _RegQueryValueExDart>(
          'RegQueryValueExW',
        );
    final regCloseKey = advapi32
        .lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

    final subKey = r'Software\WhisPaste'.toNativeUtf16();
    final hKey = calloc<IntPtr>();

    try {
      var result = regOpenKeyEx(_hkeyCurrentUser, subKey, 0, _keyRead, hKey);
      if (result != _errorSuccess) return false;

      final valueName = 'InstallSource'.toNativeUtf16();
      final dataSize = calloc<Uint32>();
      final dataType = calloc<Uint32>();
      dataSize.value = 512; // bytes
      final dataBuffer = calloc<Uint8>(512);

      try {
        result = regQueryValueEx(
          hKey.value,
          valueName,
          nullptr,
          dataType,
          dataBuffer,
          dataSize,
        );
        if (result != _errorSuccess || dataType.value != _regSz) return false;

        // Decode the UTF-16 string (REG_SZ is null-terminated UTF-16).
        final charCount = (dataSize.value ~/ 2) - 1; // exclude null terminator
        if (charCount <= 0) return false;
        final value = dataBuffer.cast<Utf16>().toDartString(length: charCount);
        return value == 'installer';
      } finally {
        calloc.free(valueName);
        calloc.free(dataSize);
        calloc.free(dataType);
        calloc.free(dataBuffer);
        regCloseKey(hKey.value);
      }
    } finally {
      calloc.free(subKey);
      calloc.free(hKey);
    }
  } catch (e) {
    _log.debug('Registry check failed: $e');
    return false;
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Cached deploy channel — detected once, never changes during runtime.
final deployChannelProvider = Provider<DeployChannel>((ref) {
  return detectDeployChannel();
});
