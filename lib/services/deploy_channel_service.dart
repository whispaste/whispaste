/// Deploy channel detection — determines how WhisPaste was installed.
///
/// Three channels exist:
/// - **store**: Installed from MS Store (MSIX package identity detected)
/// - **installer**: Installed via NSIS Setup.exe (registry marker present)
/// - **portable**: Running from extracted ZIP or dev environment (fallback)
///
/// The channel determines update behavior:
/// - Store → updates managed by the Store, no in-app check needed
/// - Installer → check GitHub Releases, download & launch new Setup.exe
/// - Portable → check GitHub Releases, show notification with download link
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('DeployChannel');

/// How the app was deployed to this machine.
enum DeployChannel {
  /// Installed from Microsoft Store or other OS store (MSIX/AppX package).
  store,

  /// Installed via NSIS installer (WhisPaste-Setup.exe from GitHub).
  installer,

  /// Running from extracted ZIP, dev build, or unknown source.
  portable,
}

/// Override for testing. When non-null, [detectDeployChannel] returns this
/// instead of probing the OS.
@visibleForTesting
DeployChannel? deployChannelOverride;

/// Detects the deploy channel once.
///
/// Detection order (Windows):
/// 1. MSIX package identity → [DeployChannel.store]
/// 2. Registry marker `HKCU\Software\WhisPaste\InstallSource` → [DeployChannel.installer]
/// 3. Fallback → [DeployChannel.portable]
///
/// On non-Windows platforms, always returns [DeployChannel.portable] for now.
DeployChannel detectDeployChannel() {
  if (deployChannelOverride != null) return deployChannelOverride!;
  if (!Platform.isWindows) return DeployChannel.portable;

  // 1. Check for MSIX package identity via GetCurrentPackageFullName.
  if (_hasMsixPackageIdentity()) {
    _log.info('Deploy channel: store (MSIX package identity detected)');
    return DeployChannel.store;
  }

  // 2. Check for NSIS installer registry marker.
  if (_hasInstallerRegistryMarker()) {
    _log.info('Deploy channel: installer (registry marker found)');
    return DeployChannel.installer;
  }

  // 3. Fallback.
  _log.info('Deploy channel: portable (no store or installer marker)');
  return DeployChannel.portable;
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
    final getCurrentPackageFullName = kernel32.lookupFunction<
        Int32 Function(Pointer<Uint32> length, Pointer<Uint16> fullName),
        int Function(
            Pointer<Uint32> length, Pointer<Uint16> fullName)>(
      'GetCurrentPackageFullName',
    );

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
typedef _RegOpenKeyExNative = Int32 Function(
    IntPtr hKey, Pointer<Utf16> lpSubKey, Uint32 ulOptions,
    Uint32 samDesired, Pointer<IntPtr> phkResult);
typedef _RegOpenKeyExDart = int Function(
    int hKey, Pointer<Utf16> lpSubKey, int ulOptions,
    int samDesired, Pointer<IntPtr> phkResult);

typedef _RegQueryValueExNative = Int32 Function(
    IntPtr hKey, Pointer<Utf16> lpValueName, Pointer<Uint32> lpReserved,
    Pointer<Uint32> lpType, Pointer<Uint8> lpData, Pointer<Uint32> lpcbData);
typedef _RegQueryValueExDart = int Function(
    int hKey, Pointer<Utf16> lpValueName, Pointer<Uint32> lpReserved,
    Pointer<Uint32> lpType, Pointer<Uint8> lpData, Pointer<Uint32> lpcbData);

typedef _RegCloseKeyNative = Int32 Function(IntPtr hKey);
typedef _RegCloseKeyDart = int Function(int hKey);

/// The NSIS installer writes `InstallSource=installer` to the registry.
bool _hasInstallerRegistryMarker() {
  try {
    final advapi32 = DynamicLibrary.open('advapi32.dll');

    final regOpenKeyEx = advapi32.lookupFunction<
        _RegOpenKeyExNative, _RegOpenKeyExDart>('RegOpenKeyExW');
    final regQueryValueEx = advapi32.lookupFunction<
        _RegQueryValueExNative, _RegQueryValueExDart>('RegQueryValueExW');
    final regCloseKey = advapi32.lookupFunction<
        _RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

    final subKey = r'Software\WhisPaste'.toNativeUtf16();
    final hKey = calloc<IntPtr>();

    try {
      var result = regOpenKeyEx(
          _hkeyCurrentUser, subKey, 0, _keyRead, hKey);
      if (result != _errorSuccess) return false;

      final valueName = 'InstallSource'.toNativeUtf16();
      final dataSize = calloc<Uint32>();
      final dataType = calloc<Uint32>();
      dataSize.value = 512; // bytes
      final dataBuffer = calloc<Uint8>(512);

      try {
        result = regQueryValueEx(
            hKey.value, valueName, nullptr, dataType, dataBuffer, dataSize);
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
