/// Free disk space for a directory, for a warning before a large download
/// (UIA-ONB-09). Fail-open: `null` whenever the answer is not certain, so the
/// caller never blocks a download on a probe it could not run.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bytes the current user can still write on the volume holding a path.
typedef FreeDiskSpaceProbe = Future<int?> Function(String path);

/// Overridable in tests; the real probe asks the OS.
final freeDiskSpaceProbeProvider = Provider<FreeDiskSpaceProbe>(
  (_) => freeDiskBytes,
);

/// Free bytes available to the current user on the volume of [path], or
/// `null` when unknown. A [path] that does not exist yet (a models folder
/// before the first download) is resolved to its nearest existing parent.
Future<int?> freeDiskBytes(String path) async {
  try {
    final existing = _nearestExisting(path);
    if (existing == null) return null;
    if (Platform.isWindows) return _windowsFreeBytes(existing);
    if (Platform.isMacOS || Platform.isLinux) {
      return _statvfsFreeBytes(existing);
    }
    return null;
  } on Object {
    return null;
  }
}

String? _nearestExisting(String path) {
  var dir = Directory(path).absolute;
  while (!dir.existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return dir.path;
}

int? _windowsFreeBytes(String path) {
  final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
  final getDiskFreeSpaceExW = kernel32
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<Utf16>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
        ),
        int Function(
          ffi.Pointer<Utf16>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
        )
      >('GetDiskFreeSpaceExW');
  return using((arena) {
    final available = arena<ffi.Uint64>();
    final ok = getDiskFreeSpaceExW(
      path.toNativeUtf16(allocator: arena),
      available,
      ffi.nullptr,
      ffi.nullptr,
    );
    return ok == 0 ? null : available.value;
  });
}

/// `statvfs` through libc. Only the two fields needed are read, by offset,
/// because the struct differs: on 64-bit glibc `f_bavail` is a 64-bit count
/// at offset 32; on macOS the block counts are 32-bit (`fsblkcnt_t`), so
/// `f_bavail` is at offset 24, and libc scales `f_frsize` up to keep large
/// volumes in range. `f_frsize` is an `unsigned long` at offset 8 on both.
int? _statvfsFreeBytes(String path) {
  if (ffi.sizeOf<ffi.IntPtr>() != 8) return null;
  final statvfs = ffi.DynamicLibrary.process()
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>),
        int Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>)
      >('statvfs');
  return using((arena) {
    // Larger than either struct (glibc: 112 bytes, macOS: 64 bytes).
    final buf = arena<ffi.Uint8>(256);
    if (statvfs(path.toNativeUtf8(allocator: arena), buf) != 0) return null;
    final frsize = (buf + 8).cast<ffi.Uint64>().value;
    final bavail = Platform.isMacOS
        ? (buf + 24).cast<ffi.Uint32>().value
        : (buf + 32).cast<ffi.Uint64>().value;
    return frsize * bavail;
  });
}
