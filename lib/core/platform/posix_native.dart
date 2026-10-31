/// In-process POSIX calls for macOS.
///
/// A child process (`chmod`, `id`, `stat`) is blocked by the Mac App Store
/// sandbox, so the sandboxed build calls the C library that is already loaded
/// into the process instead. Only use these on macOS and Linux; Windows has no
/// POSIX modes.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _ChmodC = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Uint32);
typedef _ChmodDart = int Function(ffi.Pointer<Utf8>, int);

typedef _GetuidC = ffi.Uint32 Function();
typedef _GetuidDart = int Function();

typedef _StatC = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);
typedef _StatDart = int Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>);

/// Byte offset of `st_uid` in Darwin's 64-bit `struct stat` (after `st_dev`,
/// `st_mode`, `st_nlink` and `st_ino`).
const _darwinStUidOffset = 16;

/// Holds the largest `struct stat` read here (Darwin: 144 bytes).
const _statBufferSize = 256;

/// `chmod(2)` from the process's C library, loaded on first use.
final _ChmodDart _chmod = ffi.DynamicLibrary.process()
    .lookupFunction<_ChmodC, _ChmodDart>('chmod');

/// `getuid(2)`, loaded on first use.
final _GetuidDart _getuid = ffi.DynamicLibrary.process()
    .lookupFunction<_GetuidC, _GetuidDart>('getuid');

/// `stat(2)`, or `null` when no variant is exported. macOS on x86_64 exports
/// the 64-bit inode variant under a suffixed name; arm64 exports `stat`.
final _StatDart? _stat = _loadStat();

_StatDart? _loadStat() {
  final lib = ffi.DynamicLibrary.process();
  for (final name in const [r'stat$INODE64', 'stat']) {
    try {
      return lib.lookupFunction<_StatC, _StatDart>(name);
    } on ArgumentError {
      continue;
    }
  }
  return null;
}

/// Sets [path] to [mode], for example `0x1C0` for 0700. Returns `true` on
/// success.
bool nativeChmod(String path, int mode) {
  try {
    return using((arena) {
      return _chmod(path.toNativeUtf8(allocator: arena), mode) == 0;
    });
  } on Object {
    return false;
  }
}

/// Numeric uid of the current user.
int nativeGetUid() => _getuid();

/// Numeric uid owning [path] (macOS only; symlinks are followed), or `null`
/// when it cannot be read.
int? nativeOwnerUid(String path) {
  final stat = _stat;
  if (stat == null) return null;
  final buffer = calloc<ffi.Uint8>(_statBufferSize);
  try {
    return using((arena) {
      if (stat(path.toNativeUtf8(allocator: arena), buffer) != 0) return null;
      final view = ByteData.sublistView(buffer.asTypedList(_statBufferSize));
      return view.getUint32(_darwinStUidOffset, Endian.host);
    });
  } on Object {
    return null;
  } finally {
    calloc.free(buffer);
  }
}
