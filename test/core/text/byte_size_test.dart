import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/byte_size.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

const _nbsp = ' ';

void main() {
  group('formatByteSize', () {
    test('base 1000 (macOS, Linux) and base 1024 (Windows) differ', () {
      expect(
        formatByteSize(190085487, locale: 'en', base: 1000),
        '190${_nbsp}MB',
      );
      expect(
        formatByteSize(190085487, locale: 'en', base: 1024),
        '181${_nbsp}MB',
      );
    });

    test('thresholds and rounding', () {
      expect(formatByteSize(999, locale: 'en', base: 1000), '999${_nbsp}B');
      expect(formatByteSize(2000, locale: 'en', base: 1000), '2${_nbsp}KB');
      expect(
        formatByteSize(1500000, locale: 'en', base: 1000),
        '1.5${_nbsp}MB',
      );
      expect(
        formatByteSize(12500000, locale: 'en', base: 1000),
        '13${_nbsp}MB',
      );
      expect(
        formatByteSize(1300000000, locale: 'en', base: 1000),
        '1.3${_nbsp}GB',
      );
    });

    test('decimal separator follows the locale', () {
      expect(
        formatByteSize(1300000000, locale: 'de', base: 1000),
        '1,3${_nbsp}GB',
      );
      expect(
        formatByteSize(1300000000, locale: 'fr', base: 1000).contains(','),
        isTrue,
      );
    });

    test('platform default base', () {
      expect(byteSizeBase, Platform.isWindows ? 1024 : 1000);
    });
  });

  group('pinned model sizes', () {
    test('Parakeet bundle total equals the sum of its pinned files', () {
      final sum = parakeetModelFiles.fold<int>(0, (a, f) => a + f.sizeBytes);
      expect(parakeetModelTotalBytes, sum);
    });

    test('download bytes add the GGUF model only when the GPU is wanted', () {
      expect(parakeetDownloadBytes(gpuWanted: false), parakeetModelTotalBytes);
      expect(
        parakeetDownloadBytes(gpuWanted: true),
        parakeetModelTotalBytes + parakeetGgufActive.sizeBytes,
      );
    });

    test('every size label goes through the shared formatter', () {
      for (final m in sttModels) {
        expect(m.sizeLabel, formatByteSize(m.sizeBytes));
      }
      expect(
        parakeetDownloadSizeLabel(gpuWanted: true),
        formatByteSize(parakeetDownloadBytes(gpuWanted: true)),
      );
    });
  });

  test('no surface formats a byte size with its own number', () {
    // Allowlist: not download sizes (VRAM, RAM thresholds, a log line).
    const allowed = {
      'lib/core/text/byte_size.dart',
      'lib/features/settings/sections/stt_keep_loaded_rows.dart',
      'lib/features/help/manual/manual_chapters.dart',
      'lib/services/audio_service.dart',
    };
    final own = RegExp(
      r'''\$\{[^}]*(toStringAsFixed|NumberFormat)[^}]*\}\s?(KB|MB|GB)''',
    );
    final ownFormatter = RegExp(
      r'String\s+_?(formatBytes|formatSize|onboardingDownloadSize)\s*\(',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path.contains('/generated/')) continue;
      if (allowed.contains(path)) continue;
      final text = f.readAsStringSync();
      if (own.hasMatch(text) || ownFormatter.hasMatch(text)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
