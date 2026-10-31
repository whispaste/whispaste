/// Windows-only helper shared by every bundled-native-library engine
/// ([WhisperFfiEngine], [SmartModeFfiEngine]): makes the OS loader search a
/// given directory when resolving a DLL's own transitive dependencies.
///
/// Verified during v1.2.45 release prep (`whisper.dll` case): a bare
/// `DynamicLibrary.open()` on a bundled DLL fails with Win32 error 126 ("The
/// specified module could not be found") even with every dependency DLL
/// sitting right next to it — the default search order only covers the
/// directory of the original EXE for a DEPENDENCY's own dependencies, not the
/// directory of each intermediate DLL in the chain. `SetDllDirectoryW` adds
/// that directory to the search path used for those transitive lookups.
/// macOS/Linux don't need this — their `@loader_path`/`$ORIGIN` rpaths,
/// embedded into the dylibs/.so at build time, already cover it.
///
/// Safe to call back-to-back for different engines in the same process:
/// each engine calls it immediately before its own `DynamicLibrary.open`,
/// and no two of these engines are ever loaded concurrently.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

void ensureWindowsDllSearchPath(String libraryPath) {
  if (!Platform.isWindows) return;
  final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
  final setDllDirectoryW = kernel32
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf16>),
        int Function(ffi.Pointer<Utf16>)
      >('SetDllDirectoryW');
  final dirPointer = p.dirname(libraryPath).toNativeUtf16();
  try {
    setDllDirectoryW(dirPointer);
  } finally {
    malloc.free(dirPointer);
  }
}
