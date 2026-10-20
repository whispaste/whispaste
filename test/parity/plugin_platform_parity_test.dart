// Plugin platform-support guard (see .scratch/parity-review/).
//
// Every Flutter plugin among the direct dependencies in pubspec.yaml must
// declare linux, macos and windows support, or be listed in [_allowlist] with
// a reason. Packages are resolved through .dart_tool/package_config.json, so
// this test needs `flutter pub get` to have run (flutter test does that).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _required = ['linux', 'macos', 'windows'];

/// Plugin -> platform -> reason for a deliberate gap.
const _allowlist = <String, Map<String, String>>{
  'auto_updater': {
    'linux':
        'Sparkle/WinSparkle only. platformSupportsSparkle() is false on Linux, so the plugin is never called there (auto_updater_service.dart).',
  },
  'dbus': {
    'macos':
        'Pure Dart, not a Flutter plugin: its top-level pub.dev platforms list omits macos. Used only for the Linux focus sources (focused_target/dbus_focus_sources.dart).',
  },
};

/// Direct dependency names from pubspec.yaml, with their `path:` if local.
Map<String, String?> _directDependencies(String pubspec) {
  final result = <String, String?>{};
  final lines = pubspec.split('\n');
  var inDeps = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (RegExp(r'^[a-z_]+:').hasMatch(line)) {
      inDeps = line.startsWith('dependencies:');
      continue;
    }
    if (!inDeps) continue;
    final head = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (head == null) continue;
    final name = head.group(1)!;
    String? path;
    var isSdk = false;
    for (var j = i + 1; j < lines.length; j++) {
      final child = lines[j];
      if (child.isEmpty || child.startsWith('    ')) {
        final pathMatch = RegExp(r'^\s+path:\s*(\S+)').firstMatch(child);
        if (pathMatch != null) path = pathMatch.group(1);
        if (RegExp(r'^\s+sdk:').hasMatch(child)) isSdk = true;
        continue;
      }
      break;
    }
    if (!isSdk) result[name] = path;
  }
  return result;
}

/// Declared platform keys of a plugin pubspec, or null when it is not a plugin.
Set<String>? _pluginPlatforms(String pubspec) {
  // Modern plugins nest `platforms:` under `flutter: plugin:`; older ones
  // (launch_at_startup) declare it at top level. Both count as plugins.
  final hasPluginKey = RegExp(
    r'^\s+plugin:\s*$',
    multiLine: true,
  ).hasMatch(pubspec);
  final lines = pubspec.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final header = RegExp(r'^(\s*)platforms:\s*$').firstMatch(lines[i]);
    if (header == null) continue;
    final indent = header.group(1)!.length;
    final keys = <String>{};
    int? childIndent;
    for (var j = i + 1; j < lines.length; j++) {
      final line = lines[j];
      if (line.trim().isEmpty) continue;
      final lineIndent = line.length - line.trimLeft().length;
      if (lineIndent <= indent) break;
      childIndent ??= lineIndent;
      if (lineIndent != childIndent) continue;
      final key = RegExp(r'^\s*([a-z]+):').firstMatch(line);
      if (key != null) keys.add(key.group(1)!);
    }
    return keys;
  }
  return hasPluginKey ? <String>{} : null;
}

Map<String, String> _packageRoots() {
  final file = File('.dart_tool/package_config.json');
  if (!file.existsSync()) {
    fail('.dart_tool/package_config.json missing; run `flutter pub get`.');
  }
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final roots = <String, String>{};
  final base = file.absolute.parent.uri;
  for (final entry in (config['packages'] as List<dynamic>)) {
    final map = entry as Map<String, dynamic>;
    final uri = base.resolve(map['rootUri'] as String);
    roots[map['name'] as String] = uri.toFilePath();
  }
  return roots;
}

void main() {
  test('every direct Flutter plugin supports linux, macos and windows', () {
    final deps = _directDependencies(File('pubspec.yaml').readAsStringSync());
    expect(deps, isNotEmpty, reason: 'No dependencies parsed from pubspec.');
    final roots = _packageRoots();

    final problems = <String>[];
    final checked = <String>[];
    for (final entry in deps.entries) {
      final name = entry.key;
      final localPath = entry.value;
      final root = localPath ?? roots[name];
      if (root == null) {
        problems.add('$name: not found in .dart_tool/package_config.json');
        continue;
      }
      final pubspecFile = File('$root/pubspec.yaml');
      if (!pubspecFile.existsSync()) {
        problems.add('$name: pubspec not found at ${pubspecFile.path}');
        continue;
      }
      final platforms = _pluginPlatforms(pubspecFile.readAsStringSync());
      if (platforms == null) continue;
      checked.add(name);
      final allowed = _allowlist[name] ?? const <String, String>{};
      for (final platform in _required) {
        final declared = platforms.contains(platform);
        final isAllowed = allowed.containsKey(platform);
        if (!declared && !isAllowed) {
          problems.add('$name does not declare $platform support');
        }
        if (declared && isAllowed) {
          problems.add(
            '$name now declares $platform; remove its allowlist entry',
          );
        }
      }
    }

    expect(checked, isNotEmpty, reason: 'No plugins were checked.');
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
