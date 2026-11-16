/// Whether the operating system is in a low-power mode (macOS Low Power Mode,
/// Windows battery saver, Linux power-saver profile).
///
/// Automatic speech-engine re-warm is skipped while it is on. The decision and
/// the parsers are pure; [readLowPowerState] is the only platform-bound part.
/// Unknown readings never block, so a missing source cannot silently disable
/// the re-warm; they are logged by the caller.
///
/// The reading runs while memory is short (pressure reload) and right after
/// wake, so it never blocks the UI isolate (#337): the native calls run on a
/// helper isolate with pointers resolved once from the named library, and a
/// reading that does not answer within [kLowPowerReadTimeout] is unknown.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../core/platform/native_libs.dart';

/// Longest the low-power reading is waited for before it counts as unknown.
const Duration kLowPowerReadTimeout = Duration(seconds: 3);

enum LowPowerState { on, off, unknown }

/// Only a confirmed low-power mode blocks automatic warm-up.
bool lowPowerBlocksAutoWarm(LowPowerState state) => state == LowPowerState.on;

/// Parses `gdbus call … org.freedesktop.DBus.Properties.Get … ActiveProfile`,
/// e.g. `(<'power-saver'>,)`.
LowPowerState lowPowerFromPowerProfile(String gdbusOutput) {
  if (gdbusOutput.contains("'power-saver'")) return LowPowerState.on;
  if (gdbusOutput.contains("'balanced'") ||
      gdbusOutput.contains("'performance'")) {
    return LowPowerState.off;
  }
  return LowPowerState.unknown;
}

/// Maps `SYSTEM_POWER_STATUS.SystemStatusFlag`: 1 = energy saver on, 0 = off.
LowPowerState lowPowerFromWindowsSaverFlag(int flag) => switch (flag) {
  1 => LowPowerState.on,
  0 => LowPowerState.off,
  _ => LowPowerState.unknown,
};

/// Reads the current low-power state of this machine. Never throws and never
/// waits longer than [kLowPowerReadTimeout].
Future<LowPowerState> readLowPowerState() {
  if (Platform.isMacOS) {
    return runNativeProbe(
      _macLowPowerState,
      timeout: kLowPowerReadTimeout,
      fallback: LowPowerState.unknown,
    );
  }
  if (Platform.isWindows) {
    return runNativeProbe(
      _windowsLowPowerState,
      timeout: kLowPowerReadTimeout,
      fallback: LowPowerState.unknown,
    );
  }
  if (Platform.isLinux) return boundedLowPowerState(_linuxLowPowerState);
  return Future.value(LowPowerState.unknown);
}

/// Asks [read] with the time limit: a reading that hangs, fails or is slower
/// than [timeout] is [LowPowerState.unknown], which never blocks a warm-up.
/// Callers wrap their injected reader with it, so no source can hold the
/// pressure reload or the wake re-warm.
Future<LowPowerState> boundedLowPowerState(
  Future<LowPowerState> Function() read, {
  Duration timeout = kLowPowerReadTimeout,
}) => withNativeTimeout(
  Future.sync(read),
  timeout: timeout,
  fallback: LowPowerState.unknown,
);

// --- macOS: [[NSProcessInfo processInfo] isLowPowerModeEnabled] via the
// Objective-C runtime, so no helper process is started (MAS symbol rule).

typedef _ObjcLookupC = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
typedef _ObjcLookupDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
typedef _MsgSendPtrC =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    );
typedef _MsgSendPtrDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    );
typedef _MsgSendBoolC =
    ffi.Int8 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _MsgSendBoolDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);

final _ObjcLookupDart? _objcGetClass = resolveNative(
  () => libobjc?.lookupFunction<_ObjcLookupC, _ObjcLookupDart>('objc_getClass'),
);
final _ObjcLookupDart? _selRegisterName = resolveNative(
  () => libobjc?.lookupFunction<_ObjcLookupC, _ObjcLookupDart>(
    'sel_registerName',
  ),
);
final _MsgSendPtrDart? _msgSendPtr = resolveNative(
  () => libobjc?.lookupFunction<_MsgSendPtrC, _MsgSendPtrDart>('objc_msgSend'),
);
final _MsgSendBoolDart? _msgSendBool = resolveNative(
  () =>
      libobjc?.lookupFunction<_MsgSendBoolC, _MsgSendBoolDart>('objc_msgSend'),
);

LowPowerState _macLowPowerState() {
  final getClass = _objcGetClass;
  final selector = _selRegisterName;
  final msgPtr = _msgSendPtr;
  final msgBool = _msgSendBool;
  if (getClass == null ||
      selector == null ||
      msgPtr == null ||
      msgBool == null) {
    return LowPowerState.unknown;
  }
  final cls = _withCString('NSProcessInfo', getClass);
  if (cls == ffi.nullptr) return LowPowerState.unknown;
  final info = msgPtr(cls, _withCString('processInfo', selector));
  if (info == ffi.nullptr) return LowPowerState.unknown;
  final enabled = msgBool(
    info,
    _withCString('isLowPowerModeEnabled', selector),
  );
  return enabled != 0 ? LowPowerState.on : LowPowerState.off;
}

ffi.Pointer<ffi.Void> _withCString(String value, _ObjcLookupDart fn) {
  final ptr = value.toNativeUtf8();
  try {
    return fn(ptr);
  } finally {
    calloc.free(ptr);
  }
}

// --- Windows: GetSystemPowerStatus; SystemStatusFlag sits at offset 3 of the
// 12-byte SYSTEM_POWER_STATUS.

typedef _GetSystemPowerStatusC = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>);
typedef _GetSystemPowerStatusDart = int Function(ffi.Pointer<ffi.Uint8>);

const _systemPowerStatusSize = 12;
const _systemStatusFlagOffset = 3;

final _GetSystemPowerStatusDart? _getSystemPowerStatus = resolveNative(
  () => kernel32
      ?.lookupFunction<_GetSystemPowerStatusC, _GetSystemPowerStatusDart>(
        'GetSystemPowerStatus',
      ),
);

LowPowerState _windowsLowPowerState() {
  final status = _getSystemPowerStatus;
  if (status == null) return LowPowerState.unknown;
  final buffer = calloc<ffi.Uint8>(_systemPowerStatusSize);
  try {
    if (status(buffer) == 0) return LowPowerState.unknown;
    final flag = buffer.asTypedList(
      _systemPowerStatusSize,
    )[_systemStatusFlagOffset];
    return lowPowerFromWindowsSaverFlag(flag);
  } finally {
    calloc.free(buffer);
  }
}

// --- Linux: power-profiles-daemon over D-Bus. A missing service is unknown.

Future<LowPowerState> _linuxLowPowerState() async {
  final result = await Process.run('gdbus', [
    'call',
    '--system',
    '--dest',
    'net.hadess.PowerProfiles',
    '--object-path',
    '/net/hadess/PowerProfiles',
    '--method',
    'org.freedesktop.DBus.Properties.Get',
    'net.hadess.PowerProfiles',
    'ActiveProfile',
  ]).timeout(const Duration(seconds: 2));
  if (result.exitCode != 0) return LowPowerState.unknown;
  return lowPowerFromPowerProfile(result.stdout.toString());
}
