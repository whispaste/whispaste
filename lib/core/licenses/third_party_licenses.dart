/// Notices for the third-party assets WhisPaste ships or downloads — the
/// bundled fonts, the native libraries and the speech/text models — registered
/// with Flutter's [LicenseRegistry] so the in-app licenses page lists them next
/// to the Dart package licenses.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Font family → OFL text under `assets/fonts/licenses/`.
const _fontLicenses = <String, String>{
  'Hanken Grotesk': 'OFL-HankenGrotesk.txt',
  'Bricolage Grotesque': 'OFL-BricolageGrotesque.txt',
  'Inter': 'OFL-Inter.txt',
};

/// Native libraries WhisPaste links or ships (the bundled binaries and the
/// code compiled into them): licence title on the licences page → text file
/// under `assets/licenses/`. Versions in the trailing comments follow the pins
/// in `scripts/build-*.sh`, `macos/Podfile.lock` and `pubspec.lock`; each text
/// is copied from the upstream repository at that tag or commit.
const nativeLibraryLicenses = <String, String>{
  'whisper.cpp (with ggml)': 'whisper-cpp-LICENSE.txt', // v1.9.5
  'llama.cpp (with ggml)': 'llama-cpp-LICENSE.txt', // b10150
  // Vendored under linux/runner/third_party; public-domain dedication (CC0).
  'minimp3 (in the Linux build)':
      'minimp3-LICENSE.txt', // lieff/minimp3, CC0-1.0
  // Ogg/Opus decoding on Windows and macOS: pinned release tarballs, built statically.
  'libogg (in the Ogg/Opus decoder)':
      'libogg-LICENSE.txt', // 1.3.6, BSD-3-Clause
  // libFLAC is linked by the Linux build (FLAC decoding); BSD-3-Clause, libFLAC only.
  'libFLAC (in the FLAC decoder)': 'libflac-LICENSE.txt', // 1.4.3, BSD-3-Clause
  'libopus (in the Ogg/Opus decoder)':
      'libopus-LICENSE.txt', // 1.5.2, BSD-3-Clause
  'opusfile (in the Ogg/Opus decoder)':
      'opusfile-LICENSE.txt', // 0.12, BSD-3-Clause
  'nlohmann/json':
      'nlohmann-json-LICENSE.txt', // 3.12.0, in libllama-common and sherpa-onnx
  'cpp-httplib': 'cpp-httplib-LICENSE.txt', // in libllama-common
  'sherpa-onnx': 'sherpa-onnx-LICENSE.txt', // 1.13.4 (Apache-2.0)
  // Code sherpa-onnx links statically into its C API library (no TTS build);
  // the texts are copied from the source trees of the pinned build.
  'kaldi-native-fbank (in sherpa-onnx)':
      'kaldi-native-fbank-LICENSE.txt', // 1.22.3, Apache-2.0
  'kaldi-decoder (in sherpa-onnx)':
      'kaldi-decoder-LICENSE.txt', // 0.3.0, Apache-2.0
  'kaldifst (in sherpa-onnx)': 'kaldifst-LICENSE.txt', // 1.8.0, Apache-2.0
  'OpenFst (in sherpa-onnx)':
      'openfst-LICENSE.txt', // csukuangfj fork 1.8.5, Apache-2.0
  'KISS FFT (in sherpa-onnx)':
      'kissfft-LICENSE.txt', // via kaldi-native-fbank, BSD-3-Clause
  'simple-sentencepiece (in sherpa-onnx)':
      'simple-sentencepiece-LICENSE.txt', // 0.7, Apache-2.0; darts.h BSD-2, threadpool zlib
  'Eigen (in sherpa-onnx)': 'eigen-LICENSE.txt', // 5.0.1, MPL-2.0
  'ONNX Runtime': 'onnxruntime-LICENSE.txt', // 1.27.0
  'ONNX Runtime third-party notices': 'onnxruntime-ThirdPartyNotices.txt',
  'Sparkle': 'sparkle-LICENSE.txt', // 2.9.4, macOS auto-update
  'HotKey': 'hotkey-LICENSE.txt', // 0.2.1, macOS global hotkeys
  'Sentry Cocoa': 'sentry-cocoa-LICENSE.txt', // 8.58.4, macOS crash reporting
  'WinSparkle': 'winsparkle-LICENSE.txt', // 0.9.3, Windows auto-update
  'expat (in WinSparkle)': 'winsparkle-expat-LICENSE.txt',
  'SoLoud': 'soloud-LICENSE.txt', // flutter_soloud 4.0.13, audio engine
  'libXScrnSaver (Flatpak build)':
      'libxscrnsaver-LICENSE.txt', // 1.2.4, X11 (MIT-style)
};

// Bundled with the whisper.cpp library (assets/models/vad/NOTICE.md).
const _sileroVad = '''
Silero VAD v5.1.2, converted to ggml format (ggml-org/whisper-vad).

MIT License

Copyright (c) 2020-present Silero Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

// CC BY 4.0 §3(a): creator, licence link and an indication of changes.
const _parakeet = '''
Parakeet TDT 0.6B v3 by NVIDIA (nvidia/parakeet-tdt-0.6b-v3), downloaded on
request. Licensed under the Creative Commons Attribution 4.0 International
License: https://creativecommons.org/licenses/by/4.0/

Changes: the weights are used in format conversions of the original model —
GGUF (ggml-org/parakeet-GGUF) and int8 ONNX (sherpa-onnx); no retraining or
fine-tuning. Provided without warranties, as stated in the licence.''';

// Gemma 4 is Apache-2.0: the former Gemma Terms link
// (ai.google.dev/gemma/docs/gemma_4_license) redirects (301) to
// ai.google.dev/gemma/apache_2, checked 2026-10-17 (BIZ-13). The Apache text
// is the file below, which is shared with kaldi-native-fbank.
const _gemmaApacheTextFile = 'kaldi-native-fbank-LICENSE.txt';

const _gemma = '''
Gemma 4 E2B-it by Google (google/gemma-4-E2B-it), downloaded on request as a
Q4_K_M GGUF quantization (unsloth/gemma-4-E2B-it-GGUF).

Licensed under the Apache License 2.0 (Apache-2.0):
https://ai.google.dev/gemma/apache_2

''';

// The optional CUDA pack is a separate NVIDIA download, not part of WhisPaste:
// it is governed by the NVIDIA CUDA Toolkit EULA, not by the project licence.
const _cudaPack = '''
Optional CUDA acceleration pack (NVIDIA CUDA runtime libraries).

Licence: NVIDIA CUDA Toolkit End User License Agreement, version
2026-01-26 (proprietary). The pack is an optional, separate download and is
not covered by the licence of WhisPaste. The full EULA text is in
LICENSE-NVIDIA.txt inside the pack (SHA-256 starts with 95815d3a862c).
Read the licence before you install or use it:
https://docs.nvidia.com/cuda/eula/index.html

''';

/// Adds the notices once at startup, before the licenses page can open.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(_entries);
}

Stream<LicenseEntry> _entries() async* {
  for (final MapEntry(key: family, value: file) in _fontLicenses.entries) {
    yield LicenseEntryWithLineBreaks([
      family,
    ], await rootBundle.loadString('assets/fonts/licenses/$file'));
  }
  for (final MapEntry(key: name, value: file)
      in nativeLibraryLicenses.entries) {
    yield LicenseEntryWithLineBreaks([
      name,
    ], await rootBundle.loadString('assets/licenses/$file'));
  }
  yield const LicenseEntryWithLineBreaks(['Silero VAD'], _sileroVad);
  yield const LicenseEntryWithLineBreaks(['Parakeet TDT 0.6B v3'], _parakeet);
  yield const LicenseEntryWithLineBreaks([
    'NVIDIA CUDA Toolkit EULA (optional CUDA pack)',
  ], _cudaPack);
  final gemmaApache = await rootBundle.loadString(
    'assets/licenses/$_gemmaApacheTextFile',
  );
  yield LicenseEntryWithLineBreaks(['Gemma 4 E2B-it'], '$_gemma$gemmaApache');
}
