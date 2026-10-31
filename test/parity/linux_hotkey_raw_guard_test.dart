// Guard for the vendored hotkey_manager_linux (XP-5-04, see
// packages/hotkey_manager_linux/linux/keybinder_raw.h): the Linux plugin must
// bind with keybinder's raw matching, and only the Linux implementation may be
// replaced. The runtime behaviour itself is covered by
// test/scripts/keybinder_raw_test.sh on a private Xvfb display.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _vendored = 'packages/hotkey_manager_linux';

/// rootUri of [name] in .dart_tool/package_config.json (needs `pub get`).
String _rootUri(String name) {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
  return packages.firstWhere((p) => p['name'] == name)['rootUri'] as String;
}

void main() {
  test('the app resolves hotkey_manager_linux to the vendored fork', () {
    expect(_rootUri('hotkey_manager_linux'), endsWith(_vendored));
  });

  test('macOS and Windows keep the upstream hotkey plugins', () {
    for (final name in ['hotkey_manager_macos', 'hotkey_manager_windows']) {
      expect(
        _rootUri(name),
        isNot(contains('/packages/')),
        reason: '$name must not be overridden',
      );
    }
  });

  test('the plugin initialises keybinder only through the raw helper', () {
    final plugin = File(
      '$_vendored/linux/hotkey_manager_linux_plugin.cc',
    ).readAsStringSync();
    expect(plugin, contains('keybinder_init_raw();'));
    expect(
      RegExp(r'\bkeybinder_init\(\)').hasMatch(plugin),
      isFalse,
      reason: 'a plain keybinder_init() resets the matching to cooked',
    );
    final cmake = File('$_vendored/linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('"keybinder_raw.cc"'));
  });

  test('a hotkey another app holds is reported to Dart as an error', () {
    // HotkeyService only shows the conflict state when register throws.
    final plugin = File(
      '$_vendored/linux/hotkey_manager_linux_plugin.cc',
    ).readAsStringSync();
    final register = plugin.substring(
      plugin.indexOf('static FlMethodResponse* hkm_register('),
      plugin.indexOf('static FlMethodResponse* hkm_unregister('),
    );
    expect(register, contains('if (!keybinder_bind(keystring'));
    expect(register, contains('fl_method_error_response_new('));
    expect(register, contains('hotkey_id_map.erase(identifier);'));
  });

  test('the plugin maps keypad keyvals from Flutter to the main keys', () {
    // Without it the safe default Ctrl+Shift+Space binds KP_Space and fails.
    final plugin = File(
      '$_vendored/linux/hotkey_manager_linux_plugin.cc',
    ).readAsStringSync();
    expect(
      plugin,
      contains('gtk_accelerator_name(hotkey_keyval_from_flutter(key_code)'),
    );
    final cmake = File('$_vendored/linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('"flutter_keyval.cc"'));
  });

  test('secondary engines do not take over the hotkey event channel', () {
    // The overlay, dock button, side panel and snippet picker engines run
    // fl_register_plugins too; the plugin keeps one global event channel.
    final plugin = File(
      '$_vendored/linux/hotkey_manager_linux_plugin.cc',
    ).readAsStringSync();
    final register = plugin.indexOf(
      'void hotkey_manager_linux_plugin_register_with_registrar(',
    );
    expect(register, isNonNegative);
    final body = plugin.substring(register);
    final guard = body.indexOf('if (event_channel != nullptr) return;');
    expect(guard, isNonNegative);
    expect(guard, lessThan(body.indexOf('event_channel =')));
  });

  test('the raw helper turns cooked matching off after keybinder_init', () {
    final helper = File('$_vendored/linux/keybinder_raw.cc').readAsStringSync();
    final init = helper.indexOf('keybinder_init();');
    final raw = helper.indexOf('keybinder_set_use_cooked_accelerators(FALSE);');
    expect(init, isNonNegative);
    expect(raw, greaterThan(init));
  });
}
