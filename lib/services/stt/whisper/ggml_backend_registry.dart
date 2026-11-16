/// Every ggml backend-registry call the app makes, routed through
/// `wp_ffi_guard` (see `native/ffi_guard`).
///
/// Loading, enumerating or scoring a backend runs vendor code (Vulkan, CUDA,
/// Metal drivers) that can throw a C++ exception (ggml-vulkan's
/// `vk::resultCheck`, Sentry 155114205). Called directly from Dart such an
/// exception ends in `std::terminate` → `abort` with no Dart-level trace.
/// Through the guard it comes back as a [NativeCallException] that the
/// engine turns into a CPU fallback with a logged reason.
///
/// Without a guard (no `wp_ffi_guard` bundled next to the library) nothing is
/// called: every method reports "not available", so no backend module is
/// opened unguarded. The engine then fails with a clear error instead.
library;

import 'dart:ffi' as ffi;

import '../native_call_guard.dart';

/// `GGML_BACKEND_DEVICE_TYPE_CPU` (ggml.h).
const int ggmlDeviceTypeCpu = 0;

/// Entry points of ggml's backend registry, resolved from the libraries the
/// app already loaded. [guard] is `null` when `wp_ffi_guard` is missing.
class GgmlBackendRegistry {
  const GgmlBackendRegistry(this.guard);

  final NativeCallGuard? guard;

  /// Address of [name] in [lib], or `null` when it is not exported.
  static ffi.Pointer<ffi.Void>? _address(ffi.DynamicLibrary lib, String name) =>
      lib.providesSymbol(name) ? lib.lookup<ffi.Void>(name) : null;

  /// `ggml_backend_load_all_from_path(dir)` from [lib]. Returns `false` when
  /// [lib] does not export it or no guard is present. Throws
  /// [NativeCallException] when the call threw.
  bool loadAllFromPath(ffi.DynamicLibrary lib, String dir) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_load_all_from_path');
    if (g == null || fn == null) return false;
    g.callVoidCString(fn, dir);
    return true;
  }

  /// Argument-less `ggml_backend_load_all()` from [lib]. Returns `false` when
  /// [lib] does not export it or no guard is present.
  bool loadAll(ffi.DynamicLibrary lib) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_load_all');
    if (g == null || fn == null) return false;
    g.callVoid(fn);
    return true;
  }

  /// `ggml_backend_load(path)` from [lib]: the registered backend, or `null`
  /// when ggml rejected the module, the export is missing or no guard is
  /// present. Throws [NativeCallException] when the call threw.
  ffi.Pointer<ffi.Void>? loadModule(ffi.DynamicLibrary lib, String path) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_load');
    if (g == null || fn == null) return null;
    final reg = g.callPtrCString(fn, path);
    return reg == ffi.nullptr ? null : reg;
  }

  /// `ggml_backend_score()` of the module at [path], see `wpg_backend_score`.
  /// 0 without a guard: a module is never opened unguarded.
  int backendScore(String path) => guard?.backendScore(path) ?? 0;

  /// `whisper_print_system_info()` from [lib].
  String? printSystemInfo(ffi.DynamicLibrary lib) {
    final g = guard;
    final fn = _address(lib, 'whisper_print_system_info');
    if (g == null || fn == null) return null;
    return g.callCStringVoid(fn);
  }

  /// `ggml_backend_dev_count()` from [lib]; `null` when not exported or no
  /// guard is present.
  int? devCount(ffi.DynamicLibrary lib) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_dev_count');
    if (g == null || fn == null) return null;
    return g.callSizeVoid(fn);
  }

  /// `ggml_backend_dev_get(index)` from [lib]; `null` when not exported or no
  /// guard is present.
  ffi.Pointer<ffi.Void>? devGet(ffi.DynamicLibrary lib, int index) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_dev_get');
    if (g == null || fn == null) return null;
    return g.callPtrSize(fn, index);
  }

  /// `ggml_backend_dev_type(dev)` from [lib]; `null` when not exported or no
  /// guard is present.
  int? devType(ffi.DynamicLibrary lib, ffi.Pointer<ffi.Void> dev) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_dev_type');
    if (g == null || fn == null) return null;
    return g.callIntPtr(fn, dev);
  }

  /// `ggml_backend_dev_name(dev)` from [lib]; `null` when not exported, the
  /// name is null or no guard is present.
  String? devName(ffi.DynamicLibrary lib, ffi.Pointer<ffi.Void> dev) {
    final g = guard;
    final fn = _address(lib, 'ggml_backend_dev_name');
    if (g == null || fn == null) return null;
    return g.callCStringPtr(fn, dev);
  }
}
