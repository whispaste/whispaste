// Guard (#337): no native symbol lookup per call.
//
// A lookup through `DynamicLibrary.process()` is `dlsym(RTLD_DEFAULT)` and
// walks every loaded image. On a Mac under memory pressure that froze the UI
// isolate, and with it hotkeys and the tray, for minutes. Lookups therefore
// live in top-level or static `final`s (resolved once, see
// lib/core/platform/native_libs.dart). Every other place is listed below with
// its reason and its exact count, so a new per-call lookup fails here and has
// to be justified or moved.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _lookup = RegExp(
  r'DynamicLibrary\.process\(\)|DynamicLibrary\.open\(|lookupFunction\s*<|\.lookup\s*<',
);
final _cachedDeclaration = RegExp(
  r'^((late )?final |\s+static (late )?final )',
);

/// Uncached lookups by file, with the reason they are acceptable.
const _allowed = <String, (int, String)>{
  'lib/core/config/linux_keyring_lock_probe.dart': (
    14,
    'runs in its own isolate (Isolate.run), once per keyring probe',
  ),
  'lib/core/platform/linux_session_bus.dart': (
    9,
    'runs in its own isolate (Isolate.run), native timeout',
  ),
  'lib/core/utils/windows_dll_search_path.dart': (
    2,
    'once before an engine library is opened, not on a recurring path',
  ),
  'lib/services/deploy_channel_service.dart': (
    6,
    'Windows install channel, detected once per session',
  ),
  'lib/services/graceful_shutdown.dart': (
    4,
    'process exit, called once at quit',
  ),
  'lib/services/headless/package_diagnose.dart': (
    3,
    'headless package diagnosis, never in the running app',
  ),
  'lib/services/smart_mode/smart_mode_ffi_engine.dart': (
    6,
    'engine load from its own library, once per load',
  ),
  'lib/services/stt/native_call_guard.dart': (
    28,
    'guard library load, cached per path in NativeCallGuard._cache',
  ),
  'lib/services/stt/whisper/ggml_backend_registry.dart': (
    1,
    'backend registration during engine load, own library',
  ),
  'lib/services/stt/whisper/whisper_ffi_engine.dart': (
    19,
    'engine load from its own library, once per load',
  ),
  'lib/services/stt_parakeet/parakeet_bindings.dart': (
    8,
    'bindings built once per loaded library',
  ),
  'lib/services/stt_parakeet/parakeet_engine_notifier.dart': (
    2,
    'resolved once inside the engine worker isolate',
  ),
  'lib/services/stt_parakeet/parakeet_gpu_engine.dart': (
    3,
    'engine load from its own library, once per load',
  ),
  'lib/services/stt_parakeet/parakeet_speech_gate.dart': (
    8,
    'speech gate load from its own library, once per load',
  ),
  'lib/services/system_user_name.dart': (
    8,
    'runs in its own isolate (Isolate.run), once for onboarding',
  ),
};

/// Counts lookups in [source] that are not part of a top-level or static
/// `final` declaration. A declaration is found by walking back from the hit
/// to the start of its statement.
int uncachedLookups(String source) {
  final lines = source.split('\n');
  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('//')) continue;
    final hits = _lookup.allMatches(lines[i]).length;
    if (hits == 0) continue;
    var start = i;
    while (start > 0) {
      final previous = lines[start - 1].trim();
      if (previous.isEmpty ||
          previous.startsWith('//') ||
          previous.endsWith(';') ||
          previous.endsWith('{') ||
          previous.endsWith('}')) {
        break;
      }
      start--;
    }
    if (!_cachedDeclaration.hasMatch(lines[start])) count += hits;
  }
  return count;
}

void main() {
  test('the detector tells a cached lookup from a per-call one', () {
    const cached = '''
final _Fn? _fn = resolveNative(
  () => libc?.lookupFunction<_C, _D>('sysctlbyname'),
);
class A {
  static final _lib = DynamicLibrary.open('x');
}
''';
    const perCall = '''
int? read() {
  final fn = DynamicLibrary.process()
      .lookupFunction<_C, _D>('sysctlbyname');
  return fn();
}
''';
    expect(uncachedLookups(cached), 0);
    expect(uncachedLookups(perCall), 2);
  });

  test('every uncached native lookup in lib/ is listed with a reason', () {
    final found = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      final count = uncachedLookups(entity.readAsStringSync());
      if (count > 0) found[path] = count;
    }
    final expected = {
      for (final entry in _allowed.entries) entry.key: entry.value.$1,
    };
    expect(
      found,
      expected,
      reason:
          'A native lookup outside a top-level or static final runs on every '
          'call. Resolve it once (lib/core/platform/native_libs.dart), or add '
          'it here with its reason and keep the count exact.',
    );
  });
}
