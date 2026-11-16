// Checks that the committed macOS plugin files register the plugins that
// pubspec.lock resolves to, for the pre-push hook. Flutter regenerates
// macos/Flutter/GeneratedPluginRegistrant.swift on every pub get and CocoaPods
// rewrites macos/Podfile.lock on every pod install; when the committed copies
// lag behind pubspec.lock, every Mac checkout reads dirty and a Mac build
// links a plugin set nobody reviewed. scripts/sync-macos-plugins.sh writes
// both files; this check only compares plugin names, so it needs neither
// CocoaPods nor macOS.
//
// Usage: dart tool/macos_plugins.dart   (dart: imports only, no build hooks)
//   Reads .flutter-plugins-dependencies (written by pub get), each macOS
//   plugin's pubspec.yaml, and HEAD's copies of the two files.
//   Exit 0: in sync. 1: drift (printed). 2: cannot tell (printed).
import 'dart:convert';
import 'dart:io';

const registrantPath = 'macos/Flutter/GeneratedPluginRegistrant.swift';
const podfileLockPath = 'macos/Podfile.lock';

/// A macOS plugin as `flutter pub get` resolved it.
class MacosPlugin {
  const MacosPlugin(
    this.name, {
    required this.nativeBuild,
    this.pluginClass,
    this.devDependency = false,
  });

  final String name;

  /// Whether the plugin brings native code, i.e. a pod.
  final bool nativeBuild;

  /// The Swift class the registrant registers; null for FFI-only plugins.
  final String? pluginClass;

  /// Dev-dependency plugins are left out of the comparison: whether Flutter
  /// registers them depends on the build mode.
  final bool devDependency;
}

/// The `pluginClass` of the `macos:` platform in a plugin's pubspec.yaml.
/// Any `macos:` block counts: the top-level `platforms:` that pub.dev reads
/// has an empty one, which simply holds no pluginClass.
String? macosPluginClass(String pubspec) {
  int? macosIndent;
  for (final line in const LineSplitter().convert(pubspec)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    if (macosIndent != null && indent <= macosIndent) macosIndent = null;
    if (macosIndent != null) {
      final m = RegExp(r'^\s*pluginClass:\s*(\S+)').firstMatch(line);
      if (m != null) return m.group(1)!.replaceAll(RegExp('''['"]'''), '');
    } else if (RegExp(r'^\s*macos:\s*$').hasMatch(line)) {
      macosIndent = indent;
    }
  }
  return null;
}

/// What differs between the resolved [plugins] and the committed
/// [registrant] and [podfileLock]; empty when they agree.
List<String> macosPluginDrift({
  required List<MacosPlugin> plugins,
  required String registrant,
  required String podfileLock,
}) {
  final ignored = {
    for (final p in plugins)
      if (p.devDependency) p.name,
  };
  final expectedPods = {
    for (final p in plugins)
      if (!p.devDependency && p.nativeBuild) p.name,
  };
  final expectedRegistered = {
    for (final p in plugins)
      if (!p.devDependency && p.pluginClass != null) p.name,
  };
  final pods = {
    for (final m in RegExp(
      r'^  - (\S+) \(from ',
      multiLine: true,
    ).allMatches(_section(podfileLock, 'DEPENDENCIES')))
      m.group(1)!,
  }..remove('FlutterMacOS');
  final registered = {
    for (final m in RegExp(
      r'^import (\w+)\s*$',
      multiLine: true,
    ).allMatches(registrant))
      m.group(1)!,
  }..removeAll(const ['Foundation', 'FlutterMacOS']);

  return [
    ..._diff(podfileLockPath, expectedPods, pods.difference(ignored)),
    ..._diff(
      registrantPath,
      expectedRegistered,
      registered.difference(ignored),
    ),
  ];
}

Iterable<String> _diff(String file, Set<String> expected, Set<String> actual) {
  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  return [
    if (missing.isNotEmpty) '$file lacks ${missing.join(', ')}',
    if (extra.isNotEmpty) '$file still lists ${extra.join(', ')}',
  ];
}

/// The lines of a top-level Podfile.lock section, up to the next one.
String _section(String lock, String name) {
  final start = lock.indexOf('\n$name:\n');
  if (start < 0) return '';
  final body = lock.substring(start + name.length + 3);
  final end = RegExp(r'^\S', multiLine: true).firstMatch(body);
  return end == null ? body : body.substring(0, end.start);
}

String _headFile(String path) {
  final r = Process.runSync('git', ['show', 'HEAD:$path']);
  if (r.exitCode != 0) throw StateError('git show HEAD:$path failed');
  return r.stdout as String;
}

void main() {
  final List<MacosPlugin> plugins;
  final String registrant;
  final String podfileLock;
  try {
    final deps =
        jsonDecode(File('.flutter-plugins-dependencies').readAsStringSync())
            as Map<String, dynamic>;
    final macos = (deps['plugins'] as Map<String, dynamic>)['macos'] as List;
    plugins = [
      for (final p in macos.cast<Map<String, dynamic>>())
        MacosPlugin(
          p['name'] as String,
          nativeBuild: p['native_build'] as bool? ?? true,
          devDependency: p['dev_dependency'] as bool? ?? false,
          pluginClass: macosPluginClass(
            File('${p['path']}pubspec.yaml').readAsStringSync(),
          ),
        ),
    ];
    registrant = _headFile(registrantPath);
    podfileLock = _headFile(podfileLockPath);
  } on Object catch (e) {
    stderr.writeln('macos_plugins: cannot tell ($e)');
    exit(2);
  }

  final drift = macosPluginDrift(
    plugins: plugins,
    registrant: registrant,
    podfileLock: podfileLock,
  );
  for (final line in drift) {
    stdout.writeln(line);
  }
  exit(drift.isEmpty ? 0 : 1);
}
