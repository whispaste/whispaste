/// System libraries for in-process native probes, opened once by name.
///
/// Rule (#337): no symbol lookup on the UI isolate while the app runs. A
/// lookup through `DynamicLibrary.process()` is `dlsym(RTLD_DEFAULT)`, which
/// walks the export tries of every loaded image. Under memory pressure each of
/// those pages has to be read back in, and on macOS the UI isolate runs on the
/// main thread, so a lookup there froze hotkeys and the tray for minutes.
/// Probes therefore keep their function pointers in top-level `final`s
/// resolved from one named library, and a probe that may still block runs off
/// the UI isolate through [runNativeProbe] with a time limit and a fallback.
/// `test/core/platform/native_lookup_guard_test.dart` enforces this.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

/// The C library: `libSystem` on macOS (opened by path, so a lookup walks only
/// its re-exported images), the process' own C library on Linux, `null` on
/// Windows or when it cannot be opened.
final ffi.DynamicLibrary? libc = Platform.isWindows
    ? null
    : resolveNative(
        () => Platform.isMacOS
            ? ffi.DynamicLibrary.open('/usr/lib/libSystem.B.dylib')
            : ffi.DynamicLibrary.process(),
      );

/// The Objective-C runtime on macOS, `null` elsewhere.
final ffi.DynamicLibrary? libobjc = Platform.isMacOS
    ? resolveNative(() => ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib'))
    : null;

/// `kernel32.dll` on Windows, `null` elsewhere.
final ffi.DynamicLibrary? kernel32 = Platform.isWindows
    ? resolveNative(() => ffi.DynamicLibrary.open('kernel32.dll'))
    : null;

/// Runs [lookup] once for a top-level `final`; a missing symbol or library
/// becomes `null` instead of an error on every later call.
T? resolveNative<T extends Object>(T? Function() lookup) {
  try {
    return lookup();
  } on ArgumentError {
    return null;
  }
}

/// Runs the synchronous [probe] on a short-lived helper isolate, so a probe
/// that blocks (page-in, a slow driver) stalls only that isolate. Answers
/// [fallback] when the probe throws or does not finish within [timeout]; the
/// helper isolate is then left to finish on its own.
///
/// At most one helper isolate runs per [probe]: a caller that arrives while
/// an earlier run is still going (a second poller, or a run that outlived its
/// time limit) waits on that run instead of spawning another. Otherwise a
/// probe that hangs for good would leave one more stuck isolate behind on
/// every poll. Pass a top-level function, so repeated calls share the key.
Future<T> runNativeProbe<T>(
  T Function() probe, {
  required Duration timeout,
  required T fallback,
}) {
  // Block body on purpose: `remove` returns this very future, and
  // `whenComplete` would wait on a returned future, so it would never finish.
  final running = _probesInFlight[probe] ??= Isolate.run<Object?>(probe)
      .whenComplete(() {
        _probesInFlight.remove(probe);
      });
  return withNativeTimeout(
    running.then((value) => value as T),
    timeout: timeout,
    fallback: fallback,
  );
}

/// Helper-isolate runs not finished yet, by probe.
final _probesInFlight = <Function, Future<Object?>>{};

/// Waits at most [timeout] for [future] and answers [fallback] on timeout or
/// error. Split from [runNativeProbe] so the time limit is testable with
/// simulated time.
Future<T> withNativeTimeout<T>(
  Future<T> future, {
  required Duration timeout,
  required T fallback,
}) async {
  try {
    return await future.timeout(timeout, onTimeout: () => fallback);
  } on Object {
    return fallback;
  }
}
