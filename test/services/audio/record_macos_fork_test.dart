// Guard for the vendored record_macos (packages/record_macos): stopping a take
// must stop the AVAudioEngine before voice processing is switched, because
// AVAudioIONode only allows that on a stopped engine. Switching it on the
// running engine crashed the CoreAudio IO thread during stop (SIGSEGV at 0x0
// in HALC_ProxyIOContext::IOWorkLoop, 2026-10-28).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _vendored = 'packages/record_macos';
const _delegate =
    '$_vendored/macos/record_macos/Sources/record_macos/delegate/'
    'RecorderStreamDelegate.swift';

/// rootUri of [name] in .dart_tool/package_config.json (needs `pub get`).
String _rootUri(String name) {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
  return packages.firstWhere((p) => p['name'] == name)['rootUri'] as String;
}

/// Body of `func stop()` up to the next member.
String _stopBody() {
  final source = File(_delegate).readAsStringSync();
  final start = source.indexOf('func stop() -> String? {');
  expect(start, isNonNegative);
  return source.substring(start, source.indexOf('func pause()', start));
}

void main() {
  test('the app resolves record_macos to the vendored fork', () {
    expect(_rootUri('record_macos'), endsWith(_vendored));
  });

  test('stop() stops the engine before it touches voice processing', () {
    final stop = _stopBody();
    final engineStop = stop.indexOf('engine.stop()');
    final voiceProcessing = stop.indexOf('setVoiceProcessing(');
    expect(engineStop, isNonNegative);
    expect(voiceProcessing, greaterThan(engineStop));
  });

  test('stop() leaves voice processing alone when the take never used it', () {
    final stop = _stopBody();
    final guard = stop.indexOf(
      'if config?.echoCancel == true || config?.autoGain == true {',
    );
    expect(guard, isNonNegative);
    expect(stop.indexOf('setVoiceProcessing('), greaterThan(guard));
  });
}
