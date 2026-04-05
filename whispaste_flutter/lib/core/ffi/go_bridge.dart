import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bridge to the Go shared library (libwhispaste).
///
/// Provides GPU detection, backend recommendation, and version info.
/// All string-returning functions allocate via Go — the bridge frees them.
class GoBridge {
  GoBridge._();

  static GoBridge? _instance;
  static DynamicLibrary? _lib;

  /// Singleton accessor. Returns null if the native library is unavailable.
  static GoBridge? get instance {
    if (_instance != null) return _instance;
    final lib = _loadLibrary();
    if (lib == null) return null;
    _lib = lib;
    _instance = GoBridge._();
    return _instance;
  }

  static DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isWindows) {
        return DynamicLibrary.open('libwhispaste.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libwhispaste.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libwhispaste.dylib');
      }
    } on ArgumentError {
      // Library not found — graceful fallback
      return null;
    }
    return null;
  }

  // --- Native function typedefs ---

  late final _detectGPU = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'DetectGPU');

  late final _recommendBackend = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'RecommendBackend');

  late final _recommendSTTAsset = _lib!.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('RecommendSTTAsset');

  late final _recommendLLMAsset = _lib!.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('RecommendLLMAsset');

  late final _getVersion = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'GetVersion');

  late final _freeString = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
          'FreeString');

  // --- Public API ---

  /// Detect GPU hardware. Returns parsed [GpuInfo].
  GpuInfo detectGPU() {
    final ptr = _detectGPU();
    final json = ptr.toDartString();
    _freeString(ptr);
    return GpuInfo.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Recommended inference backend: "cuda", "vulkan", or "cpu".
  String recommendBackend() {
    final ptr = _recommendBackend();
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }

  /// Recommended STT server download asset key.
  ///
  /// [gpuMode]: "auto", "enabled", or "disabled".
  String recommendSTTAsset({String gpuMode = 'auto'}) {
    final modePtr = gpuMode.toNativeUtf8();
    final ptr = _recommendSTTAsset(modePtr);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(modePtr);
    return result;
  }

  /// Recommended LLM server download asset key.
  ///
  /// [gpuMode]: "auto", "enabled", or "disabled".
  String recommendLLMAsset({String gpuMode = 'auto'}) {
    final modePtr = gpuMode.toNativeUtf8();
    final ptr = _recommendLLMAsset(modePtr);
    final result = ptr.toDartString();
    _freeString(ptr);
    calloc.free(modePtr);
    return result;
  }

  /// Bridge version string.
  String getVersion() {
    final ptr = _getVersion();
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }
}

/// Detected GPU information from the Go bridge.
class GpuInfo {
  const GpuInfo({
    required this.name,
    required this.vendor,
    required this.vramMb,
    required this.backend,
    required this.driver,
    required this.detected,
  });

  factory GpuInfo.fromJson(Map<String, dynamic> json) {
    return GpuInfo(
      name: json['name'] as String? ?? '',
      vendor: json['vendor'] as String? ?? 'unknown',
      vramMb: json['vram_mb'] as int? ?? 0,
      backend: json['backend'] as String? ?? 'cpu',
      driver: json['driver'] as String? ?? '',
      detected: json['detected'] as bool? ?? false,
    );
  }

  /// No GPU detected — CPU fallback.
  static const none = GpuInfo(
    name: '',
    vendor: 'unknown',
    vramMb: 0,
    backend: 'cpu',
    driver: '',
    detected: false,
  );

  final String name;
  final String vendor;
  final int vramMb;
  final String backend;
  final String driver;
  final bool detected;

  Map<String, dynamic> toJson() => {
        'name': name,
        'vendor': vendor,
        'vram_mb': vramMb,
        'backend': backend,
        'driver': driver,
        'detected': detected,
      };

  @override
  String toString() =>
      detected ? '$name ($vendor, ${vramMb}MB, $backend)' : 'No GPU detected';
}
