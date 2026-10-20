import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/licenses/third_party_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fonts and models are listed on the licenses page', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = {for (final e in entries) ...e.packages};

    for (final name in [
      'Hanken Grotesk',
      'Bricolage Grotesque',
      'Inter',
      'Silero VAD',
      'Parakeet TDT 0.6B v3',
      'Gemma 4 E2B-it',
    ]) {
      expect(packages, contains(name));
    }

    String textOf(String package) => entries
        .firstWhere((e) => e.packages.contains(package))
        .paragraphs
        .map((p) => p.text)
        .join('\n');

    expect(textOf('Hanken Grotesk'), contains('SIL Open Font License'));
    expect(textOf('Silero VAD'), contains('Silero Team'));
    // CC BY 4.0 asks for creator, licence link and a note on changes.
    final parakeet = textOf('Parakeet TDT 0.6B v3');
    expect(parakeet, contains('NVIDIA'));
    expect(parakeet, contains('creativecommons.org/licenses/by/4.0'));
    expect(parakeet, contains('GGUF'));
    // Gemma 4 is Apache-2.0 per ai.google.dev/gemma/apache_2 (BIZ-13): the
    // licence ID and link must be named, and the Apache text must follow.
    final gemma = textOf('Gemma 4 E2B-it');
    expect(gemma, contains('Apache License 2.0 (Apache-2.0)'));
    expect(gemma, contains('https://ai.google.dev/gemma/apache_2'));
    expect(gemma, contains('Version 2.0, January 2004'));
    expect(gemma, isNot(contains('Gemma Terms of Use')));
    // The optional CUDA pack is NVIDIA's proprietary EULA, not the project's.
    final cuda = textOf('NVIDIA CUDA Toolkit EULA (optional CUDA pack)');
    expect(cuda, contains('proprietary'));
    expect(cuda, contains('not covered by the licence of WhisPaste'));
    expect(cuda, contains('https://docs.nvidia.com/cuda/eula/index.html'));
    expect(cuda, contains('version 2026-01-26'));
    expect(cuda, contains('SHA-256 starts with 95815d3a862c'));
    expect(cuda, contains('LICENSE-NVIDIA.txt'));
  });

  test('the full ONNX Runtime third-party notices ship, not an excerpt', () {
    final notices = File(
      'assets/licenses/onnxruntime-ThirdPartyNotices.txt',
    ).readAsStringSync();
    // The upstream file is ~325 KB with every bundled component's notice.
    expect(notices.length, greaterThan(300000));
    expect(notices, contains('Intel Math Kernel Library'));
    expect(
      notices.trimRight(),
      endsWith('EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'),
    );
  });

  test('no shipped licence text names espeak-ng or piper', () {
    // espeak-ng (GPL-3.0-or-later) and piper-phonemize are compiled out of the
    // sherpa-onnx build WhisPaste ships (TTS=OFF), so neither may be listed.
    for (final file in Directory('assets/licenses').listSync()) {
      final text = File(file.path).readAsStringSync().toLowerCase();
      expect(text, isNot(contains('espeak')), reason: file.path);
      expect(text, isNot(contains('piper')), reason: file.path);
    }
  });

  test(
    'every native library has a registered, non-empty licence text',
    () async {
      registerThirdPartyLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final packages = {for (final e in entries) ...e.packages};

      for (final MapEntry(key: name, value: file)
          in nativeLibraryLicenses.entries) {
        expect(packages, contains(name), reason: 'no licence entry for $name');
        final asset = File('assets/licenses/$file');
        expect(asset.existsSync(), isTrue, reason: '$file is missing');
        expect(
          asset.readAsStringSync().trim(),
          isNotEmpty,
          reason: '$file is empty',
        );
      }

      String textOf(String package) => entries
          .firstWhere((e) => e.packages.contains(package))
          .paragraphs
          .map((p) => p.text)
          .join('\n');

      expect(textOf('whisper.cpp (with ggml)'), contains('The ggml authors'));
      expect(textOf('llama.cpp (with ggml)'), contains('The ggml authors'));
      expect(textOf('ONNX Runtime'), contains('Microsoft Corporation'));
      expect(textOf('sherpa-onnx'), contains('Apache License'));
      expect(
        textOf('ONNX Runtime third-party notices'),
        contains('Intel Math Kernel Library'),
      );
    },
  );
}
