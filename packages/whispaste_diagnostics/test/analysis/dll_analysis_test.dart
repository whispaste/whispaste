/// Unit tests for dll_analysis.dart (AC1, AC2).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/analysis/dll_analysis.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Expected DLL set (AC1: documented, AC2: spike decision justified)
  // ---------------------------------------------------------------------------

  group('kExpectedWhisperServerDlls', () {
    test('contains VC++ runtime DLLs', () {
      expect(kExpectedWhisperServerDlls, contains('vcruntime140.dll'));
      expect(kExpectedWhisperServerDlls, contains('msvcp140.dll'));
    });

    test('contains at least one ggml backend DLL', () {
      // CPU floor always ships ggml-cpu.dll.
      expect(kExpectedWhisperServerDlls, contains('ggml-cpu.dll'));
    });
  });

  // ---------------------------------------------------------------------------
  // DllAnalysisResult — healthy (no missing DLLs)
  // ---------------------------------------------------------------------------

  group('analyzeDllDeps — healthy', () {
    test('no missing DLLs when every expected DLL is present', () {
      final result = analyzeDllDeps(
        presentDlls: kExpectedWhisperServerDlls.toSet(),
        backend: 'cpu',
      );
      expect(result.missingDlls, isEmpty);
      expect(result.vcRuntimeMissing, isFalse);
      expect(result.backendLoaderMissing, isNull);
    });

    test('non-Windows: empty present set still shows no VC++ missing', () {
      // On non-Windows the VC++ concept is irrelevant —
      // the result reflects that nothing is "missing" for the platform.
      final result = analyzeDllDeps(
        presentDlls: const <String>{},
        backend: null,
        windowsContext: false,
      );
      expect(result.missingDlls, isEmpty);
      expect(result.vcRuntimeMissing, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // DllAnalysisResult — missing DLLs
  // ---------------------------------------------------------------------------

  group('analyzeDllDeps — missing DLLs', () {
    test('detects missing vcruntime140.dll', () {
      final present = kExpectedWhisperServerDlls.toSet()
        ..remove('vcruntime140.dll');
      final result = analyzeDllDeps(presentDlls: present, backend: 'cpu');
      expect(result.missingDlls, contains('vcruntime140.dll'));
      expect(result.vcRuntimeMissing, isTrue);
    });

    test('detects missing msvcp140.dll', () {
      final present = kExpectedWhisperServerDlls.toSet()
        ..remove('msvcp140.dll');
      final result = analyzeDllDeps(presentDlls: present, backend: 'cpu');
      expect(result.missingDlls, contains('msvcp140.dll'));
      expect(result.vcRuntimeMissing, isTrue);
    });

    test('missing non-VC++ DLL: vcRuntimeMissing stays false', () {
      final present = kExpectedWhisperServerDlls.toSet()
        ..remove('ggml-cpu.dll');
      final result = analyzeDllDeps(presentDlls: present, backend: 'cpu');
      expect(result.missingDlls, contains('ggml-cpu.dll'));
      expect(result.vcRuntimeMissing, isFalse);
    });

    test('missing vulkan backend loader for vulkan backend', () {
      // vulkan-1.dll absent but VC++ present.
      final present = kExpectedWhisperServerDlls.toSet()
        ..remove('vulkan-1.dll');
      final result = analyzeDllDeps(presentDlls: present, backend: 'vulkan');
      expect(result.backendLoaderMissing, 'vulkan-1.dll');
    });

    test('cuda backend missing cudart', () {
      final present = kExpectedWhisperServerDlls.toSet();
      // cudart64_12.dll is NOT in kExpectedWhisperServerDlls (system DLL).
      final result = analyzeDllDeps(presentDlls: present, backend: 'cuda');
      expect(result.backendLoaderMissing, 'cudart64_12.dll');
    });
  });

  // ---------------------------------------------------------------------------
  // buildDllPresenceSet helper
  // ---------------------------------------------------------------------------

  group('buildDllPresenceSet', () {
    test('lower-cases all names', () {
      final result = buildDllPresenceSet(['VCRUNTIME140.DLL', 'ggml-cpu.dll']);
      expect(result, contains('vcruntime140.dll'));
      expect(result, contains('ggml-cpu.dll'));
    });

    test('empty list gives empty set', () {
      expect(buildDllPresenceSet([]), isEmpty);
    });
  });
}
