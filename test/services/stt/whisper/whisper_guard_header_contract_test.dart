/// Static contract between the Dart side of `wp_ffi_guard` and its C side.
///
/// No native library is loaded, so this runs on every host and in CI. It
/// catches the drift that would otherwise only show up at runtime as a
/// silent CPU fallback (`NativeCallGuard.load` rejects an ABI mismatch and
/// `supportsWhisperStructs` turns GPU backends off):
///
/// * the ABI version in `ffi_guard.h` equals [NativeCallGuard.abiVersion];
/// * every `wpg_*` symbol the Dart side looks up is declared by the C side;
/// * every build path builds the guard against the one whisper.cpp pin in
///   `scripts/whisper-cpp.pin` (same headers as libwhisper, so the struct
///   layouts match).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/native_call_guard.dart';

const _header = 'native/ffi_guard/ffi_guard.h';
const _selftest = 'native/ffi_guard/ffi_guard_selftest.cpp';
const _dartSide = 'lib/services/stt/native_call_guard.dart';
const _buildScripts = <String>[
  'scripts/build-libwhisper-macos.sh',
  'scripts/build-libwhisper-linux.sh',
  'scripts/build-cuda-pack-linux.sh',
];
const _windowsBuildScript = 'scripts/build-libwhisper-windows.ps1';
const _pinFile = 'scripts/whisper-cpp.pin';
const _releaseWorkflow = '.github/workflows/release.yml';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

String _single(RegExp pattern, String text, String what) {
  final match = pattern.firstMatch(text);
  expect(match, isNotNull, reason: 'no $what found');
  return match!.group(1)!;
}

void main() {
  test('WPG_ABI_VERSION in ffi_guard.h matches NativeCallGuard.abiVersion', () {
    final header = _read(_header);
    final cAbi = int.parse(
      _single(
        RegExp(r'#define WPG_ABI_VERSION\s+(\d+)'),
        header,
        'WPG_ABI_VERSION',
      ),
    );
    expect(
      NativeCallGuard.abiVersion,
      cAbi,
      reason:
          'Dart expects ABI ${NativeCallGuard.abiVersion}, the C header says '
          '$cAbi. Bump both sides together, or every guard is rejected.',
    );
  });

  test('every wpg_* symbol the Dart side looks up is declared in C', () {
    final dartSymbols = RegExp(
      r"'(wpg_[a-z0-9_]+)'",
    ).allMatches(_read(_dartSide)).map((m) => m.group(1)!).toSet();
    expect(dartSymbols, isNotEmpty);

    final cSide = _read(_header) + _read(_selftest);
    final missing = [
      for (final symbol in dartSymbols)
        if (!RegExp('\\b$symbol\\s*\\(').hasMatch(cSide)) symbol,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'Dart looks up symbols that the guard does not export',
    );
  });

  test('all build paths use the same whisper.cpp pin for the guard', () {
    final pin = _read(_pinFile);
    _single(
      RegExp(r'^WHISPER_COMMIT=([0-9a-f]{40})$', multiLine: true),
      pin,
      'WHISPER_COMMIT in $_pinFile',
    );
    _single(
      RegExp(r'^WHISPER_TAG=(v[0-9.]+)$', multiLine: true),
      pin,
      'WHISPER_TAG in $_pinFile',
    );

    // Every build path reads the one pin and names no version of its own.
    final ownVersion = RegExp(
      r'''^\s*\$?WHISPER_(TAG|COMMIT|PINNED_COMMIT)\s*=\s*["']?(v[0-9]|[0-9a-f]{40})''',
      multiLine: true,
    );
    for (final path in [..._buildScripts, _windowsBuildScript]) {
      final text = _read(path);
      expect(
        text.contains('whisper-cpp.pin'),
        isTrue,
        reason: '$path must read $_pinFile',
      );
      expect(
        ownVersion.hasMatch(text),
        isFalse,
        reason: '$path names its own whisper.cpp version',
      );
    }

    // The release workflow loads the pin and clones exactly that tag.
    final workflow = _read(_releaseWorkflow);
    expect(
      RegExp(
        r"grep -E '\^WHISPER_\(TAG\|COMMIT\)=' scripts/whisper-cpp\.pin",
      ).allMatches(workflow),
      isNotEmpty,
      reason: 'release.yml does not load $_pinFile',
    );
    final clones = RegExp(
      r'git clone --depth 1 --branch (\$\{\{ env\.\w+ \}\}|\S+) '
      r'https://github\.com/ggml-org/whisper\.cpp',
    ).allMatches(workflow).map((m) => m.group(1)!).toSet();
    expect(clones, isNotEmpty);
    expect(clones, {
      r'${{ env.WHISPER_TAG }}',
    }, reason: 'release.yml clones a whisper.cpp tag other than the pin');
  });

  test('every guard build passes WHISPER_SOURCE_DIR (headers of the pin)', () {
    for (final script in [..._buildScripts, _releaseWorkflow]) {
      final text = _read(script);
      final guardBuilds = RegExp(r'native/ffi_guard').allMatches(text).length;
      if (guardBuilds == 0) continue;
      expect(
        RegExp(r'WHISPER_SOURCE_DIR=|-DWHISPER_SOURCE_DIR').hasMatch(text),
        isTrue,
        reason: '$script builds the guard without WHISPER_SOURCE_DIR',
      );
    }
  });
}
