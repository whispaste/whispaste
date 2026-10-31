// Render-channel parity guard. The generic render channels get their channel
// name at runtime, so platform_channel_parity_test.dart cannot attribute their
// calls (its _unresolvedAllowlist). Every method a render engine invokes must
// still end in a native reply on each desktop platform: an unhandled one
// raises MissingPluginException in that engine. Matches are real dispatch
// cases (Swift `case "x"`, C++ `method == "x"`, `strcmp(method, "x")`) after
// comments are stripped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Render channel (Dart) -> native host per platform.
const _hosts = <String, Map<String, String>>{
  'lib/services/side_panel/side_panel_render_channel.dart': {
    'macos': 'macos/Runner/SidePanelHost.swift',
    'windows': 'windows/runner/side_panel_host.cpp',
    'linux': 'linux/runner/side_panel_host.cc',
  },
  'lib/services/floating_button/floating_button_render_channel.dart': {
    'macos': 'macos/Runner/FloatingButtonHost.swift',
    'windows': 'windows/runner/floating_button_host.cpp',
    'linux': 'linux/runner/floating_button_host.cc',
  },
  'lib/services/floating_overlay/overlay_render_channel.dart': {
    'macos': 'macos/Runner/FloatingOverlayHost.swift',
    'windows': 'windows/runner/floating_overlay_host.cpp',
    'linux': 'linux/runner/floating_overlay_host.cc',
  },
  'lib/services/snippet_picker/snippet_picker_render_channel.dart': {
    'macos': 'macos/Runner/SnippetPickerHost.swift',
    'windows': 'windows/runner/snippet_picker_host.cpp',
    'linux': 'linux/runner/snippet_picker_host.cc',
  },
};

final _dartCall = RegExp(r"invokeMethod(?:<[^>]*>)?\(\s*'([A-Za-z]\w*)'");
final _nativeCase = RegExp(
  r'''case\s+"([A-Za-z]\w*)"|method\s*==\s*"([A-Za-z]\w*)"|strcmp\(\s*method\s*,\s*"([A-Za-z]\w*)"\s*\)''',
);

String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

Set<String> _matches(RegExp pattern, String source) => {
  for (final m in pattern.allMatches(_stripComments(source)))
    m.groups(List.generate(m.groupCount, (i) => i + 1)).nonNulls.first,
};

void main() {
  for (final MapEntry(key: dartFile, value: hosts) in _hosts.entries) {
    test('every render call in $dartFile has a native handler', () {
      final calls = _matches(_dartCall, File(dartFile).readAsStringSync());
      expect(calls, isNotEmpty, reason: 'no invokeMethod found in $dartFile');
      final missing = <String>[
        for (final MapEntry(key: platform, value: host) in hosts.entries)
          for (final method in calls.difference(
            _matches(_nativeCase, File(host).readAsStringSync()),
          ))
            '$platform ($host): $method',
      ];
      expect(missing, isEmpty);
    });
  }
}
