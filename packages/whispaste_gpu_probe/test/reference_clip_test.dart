import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
  late ReferenceClipProvider provider;

  setUp(() {
    provider = ReferenceClipProvider();
  });

  group('ReferenceClipProvider', () {
    test('resolves short clip', () {
      final clip = provider.clip(ClipLength.short);
      expect(clip.length, ClipLength.short);
      expect(clip.language, 'de');
      expect(clip.wavPath, isNotEmpty);
      expect(clip.transcriptPath, isNotEmpty);
    });

    test('resolves long clip', () {
      final clip = provider.clip(ClipLength.long);
      expect(clip.length, ClipLength.long);
      expect(clip.language, 'de');
      expect(clip.wavPath, isNotEmpty);
      expect(clip.transcriptPath, isNotEmpty);
    });

    test('short WAV file exists and is non-empty', () {
      final clip = provider.clip(ClipLength.short);
      final file = File(clip.wavPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'WAV not found at ${clip.wavPath}',
      );
      expect(file.lengthSync(), greaterThan(0));
    });

    test('long WAV file exists and is non-empty', () {
      final clip = provider.clip(ClipLength.long);
      final file = File(clip.wavPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'WAV not found at ${clip.wavPath}',
      );
      expect(file.lengthSync(), greaterThan(0));
    });

    test('short transcript file exists and is non-empty', () {
      final clip = provider.clip(ClipLength.short);
      final file = File(clip.transcriptPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Transcript not found at ${clip.transcriptPath}',
      );
      expect(file.lengthSync(), greaterThan(0));
    });

    test('long transcript file exists and is non-empty', () {
      final clip = provider.clip(ClipLength.long);
      final file = File(clip.transcriptPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Transcript not found at ${clip.transcriptPath}',
      );
      expect(file.lengthSync(), greaterThan(0));
    });

    test('short and long WAV paths are distinct', () {
      final short = provider.clip(ClipLength.short);
      final long = provider.clip(ClipLength.long);
      expect(short.wavPath, isNot(equals(long.wavPath)));
    });
  });

  group('referenceProbeContext', () {
    test('returns ProbeContext with language de for short clip', () {
      final ctx = referenceProbeContext(
        ClipLength.short,
        modelPath: '/fake/model.bin',
        workDir: Directory.systemTemp.path,
      );
      expect(ctx.language, 'de');
      expect(ctx.referenceWavPath, isNotEmpty);
    });

    test('returns ProbeContext with language de for long clip', () {
      final ctx = referenceProbeContext(
        ClipLength.long,
        modelPath: '/fake/model.bin',
        workDir: Directory.systemTemp.path,
      );
      expect(ctx.language, 'de');
      expect(ctx.referenceWavPath, isNotEmpty);
    });

    test('short clip ProbeContext WAV file exists', () {
      final ctx = referenceProbeContext(
        ClipLength.short,
        modelPath: '/fake/model.bin',
        workDir: Directory.systemTemp.path,
      );
      expect(
        File(ctx.referenceWavPath).existsSync(),
        isTrue,
        reason: 'WAV not found at ${ctx.referenceWavPath}',
      );
    });
  });
}
