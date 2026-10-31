import 'package:flutter_test/flutter_test.dart';

import '../../tool/macos_plugins.dart';

const _plugins = [
  MacosPlugin('window_manager', nativeBuild: true, pluginClass: 'WindowPlugin'),
  MacosPlugin('sherpa_onnx_macos', nativeBuild: true),
  MacosPlugin('path_provider_foundation', nativeBuild: false),
];

const _registrant = '''
import FlutterMacOS
import Foundation

import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  WindowPlugin.register(with: registry.registrar(forPlugin: "WindowPlugin"))
}
''';

const _lock = '''
PODS:
  - FlutterMacOS (1.0.0)
  - Sparkle (2.9.6)

DEPENDENCIES:
  - FlutterMacOS (from `Flutter/ephemeral`)
  - sherpa_onnx_macos (from `Flutter/ephemeral/.symlinks/plugins/sherpa_onnx_macos/macos`)
  - window_manager (from `Flutter/ephemeral/.symlinks/plugins/window_manager/macos`)

SPEC REPOS:
  trunk:
    - Sparkle

COCOAPODS: 1.17.0
''';

List<String> _drift({
  List<MacosPlugin> plugins = _plugins,
  String registrant = _registrant,
  String lock = _lock,
}) => macosPluginDrift(
  plugins: plugins,
  registrant: registrant,
  podfileLock: lock,
);

void main() {
  test('files that name the resolved plugins are in sync', () {
    expect(_drift(), isEmpty);
  });

  test('a new plugin missing from both files is drift', () {
    expect(
      _drift(
        plugins: [
          ..._plugins,
          const MacosPlugin(
            'device_info_plus',
            nativeBuild: true,
            pluginClass: 'DeviceInfoPlusMacosPlugin',
          ),
        ],
      ),
      [
        '$podfileLockPath lacks device_info_plus',
        '$registrantPath lacks device_info_plus',
      ],
    );
  });

  test('a removed plugin still listed is drift', () {
    expect(_drift(plugins: _plugins.skip(1).toList()), [
      '$podfileLockPath still lists window_manager',
      '$registrantPath still lists window_manager',
    ]);
  });

  test('dev-dependency plugins are not compared', () {
    expect(
      _drift(
        plugins: [
          ..._plugins,
          const MacosPlugin(
            'integration_test',
            nativeBuild: true,
            pluginClass: 'IntegrationTestPlugin',
            devDependency: true,
          ),
        ],
      ),
      isEmpty,
    );
  });

  group('macosPluginClass', () {
    test('reads the class of the plugin platform', () {
      const pubspec = '''
platforms:
  macos:
  windows:

flutter:
  plugin:
    platforms:
      macos:
        pluginClass: TrayManagerPlugin
      windows:
        pluginClass: TrayManagerPluginCApi
''';
      expect(macosPluginClass(pubspec), 'TrayManagerPlugin');
    });

    test('an FFI-only or Dart-only macOS plugin has none', () {
      const pubspec = '''
flutter:
  plugin:
    platforms:
      macos:
        ffiPlugin: true
        dartPluginClass: SherpaMacos
''';
      expect(macosPluginClass(pubspec), isNull);
    });
  });
}
