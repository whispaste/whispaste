// Floating button look relay parity guard (WP-95, see internal-notes).
//
// The button's shape, recording ring and resting opacity are drawn by the
// shared Dart button view. They reach the button render engine only if every
// platform host (a) accepts the keys in `setTheme`, (b) caches them for the
// ready flush, and (c) relays them to the render engine, and if every host
// still resizes the button on `setSize`. This static check covers all three
// desktop hosts. It proves the wiring exists, not how the engine draws it
// (the widget tests cover that).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';

const _hostFiles = <String, String>{
  'macos': 'macos/Runner/FloatingButtonHost.swift',
  'windows': 'windows/runner/floating_button_host.cpp',
  'linux': 'linux/runner/floating_button_host.cc',
};

const _controllerFiles = <String, String>{
  'macos': 'lib/services/floating_button/macos_floating_button_controller.dart',
  'windows':
      'lib/services/floating_button/windows_floating_button_controller.dart',
  'linux': 'lib/services/floating_button/linux_floating_button_controller.dart',
};

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('setSize resizes the button on every host', () {
    const sizePatterns = <String, String>{
      'macos': r'case "setSize":',
      'windows': r'method == "setSize"',
      'linux': r'strcmp\(method, "setSize"\) == 0',
    };
    for (final entry in sizePatterns.entries) {
      test(entry.key, () {
        expect(
          RegExp(entry.value).hasMatch(_read(_hostFiles[entry.key]!)),
          isTrue,
          reason: '${_hostFiles[entry.key]} must handle setSize',
        );
      });
    }
  });

  group('setTheme carries the look keys and relays them', () {
    test('macos sanitises shape, ring and idleOpacity', () {
      final source = _read(_hostFiles['macos']!);
      expect(source, contains('"shape"'));
      expect(source, contains('"ring"'));
      expect(source, contains('"idleOpacity"'));
      expect(
        RegExp(
          r'renderChannel\?\.invokeMethod\("setTheme", arguments: theme\)',
        ).hasMatch(source),
        isTrue,
        reason: 'the sanitised theme must reach the render engine',
      );
    });

    test('windows reads and relays shape, ring and idleOpacity', () {
      final source = _read(_hostFiles['windows']!);
      expect(source, contains('GetBool(*map, "ring"'));
      expect(source, contains('GetDouble(*map, "idleOpacity"'));
      for (final key in ['shape', 'ring', 'idleOpacity']) {
        expect(
          source,
          contains('m[EncodableValue("$key")]'),
          reason: 'RelaySetTheme must send $key',
        );
      }
    });

    test('linux reads, caches and flushes shape, ring and idleOpacity', () {
      final source = _read(_hostFiles['linux']!);
      for (final key in ['shape', 'ring', 'idleOpacity']) {
        // Once in the setTheme parse path and once in the ready flush.
        expect(
          RegExp('"$key"').allMatches(source).length,
          greaterThanOrEqualTo(2),
          reason: 'linux must parse and flush $key',
        );
      }
    });
  });

  test('every controller sends the look through setTheme', () {
    for (final entry in _controllerFiles.entries) {
      expect(
        _read(entry.value),
        contains('...look.toThemeMap()'),
        reason: '${entry.value} must spread the look into setTheme',
      );
    }
  });

  test('the Dart theme map carries every look key the hosts read', () {
    final map = const FloatingButtonLook(
      square: true,
      ring: false,
      idleOpacity: '40',
    ).toThemeMap();
    expect(map.keys, containsAll(['shape', 'ring', 'idleOpacity']));
    expect(map['idleOpacity'], 0.4);
  });
}
