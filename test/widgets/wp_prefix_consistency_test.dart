/// Guards the naming rule for the shared component layer.
///
/// ## The rule
///
/// `Wp` marks the app's **shared component vocabulary**, and that vocabulary is
/// defined by *location*: everything publicly declared under `lib/widgets/`
/// belongs to it. Widgets owned by a single feature live under `lib/features/`
/// and deliberately carry no prefix — that boundary is already the de-facto
/// convention (261 public classes under `lib/features/`, none of them
/// prefixed), this test just stops `lib/widgets/` from drifting away from it
/// again.
///
/// Concretely:
///
/// - Every public **type** (class / enum / mixin / extension / typedef)
///   declared under `lib/widgets/` starts with `Wp`. This holds regardless of
///   whether the type is atomic (`WpButton`) or composed
///   (`WpPasteCapabilityIndicator`), visual (`WpToast`), invisible
///   (`WpServiceBootstrap`), a painter (`WpOverlayPainter`), a static-only
///   namespace (`WpMotion`) or a plain result type (`WpHotkeyResult`).
/// - Every public **`show*` function** that is a component's own public API
///   uses the `showWp*` infix — `showWpConfirmDialog`, `showWpFormDialog`,
///   `showWpExportFormatPicker`. The verb stays in front; the prefix marks the
///   thing being shown.
///
/// ## What is deliberately *not* covered
///
/// - **Filenames.** Files inside `lib/widgets/` are already namespaced by the
///   folder, so a `wp_` filename prefix adds nothing; the folder currently
///   mixes both spellings and normalising it in either direction would be pure
///   churn across every import in the repo. The one filename that was wrong for
///   a real reason — `model_download_card.dart` exporting `SttModelManager` —
///   was renamed to `wp_stt_model_manager.dart`. Filenames are expected to
///   describe their class, not to repeat the prefix.
/// - **Private declarations** (`_FooState`, `_ToolbarButton`). They are not API.
///   By convention the state class of a public widget still mirrors its
///   widget's name (`_WpServiceBootstrapState`).
/// - **The symbols in [_documentedExceptions]** below. Each one carries the
///   reason for its exemption as a comment at its own declaration; this list is
///   only the machine-readable mirror of those comments. Adding an entry here
///   without that comment defeats the purpose.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Public symbols under `lib/widgets/` that intentionally carry no prefix.
///
/// The authoritative reason lives as a comment at each declaration — see the
/// `Wp naming —` notes in the listed files.
const _documentedExceptions = <String, String>{
  // lib/widgets/hotkey_recorder.dart — hotkey domain data shared with the
  // service-layer key resolver, not a component.
  'singleKeyWhitelist': 'hotkey domain data, not a component',

  // lib/widgets/status_bar.dart — pure predicate over settings.
  'shouldShowAutoPasteOffHint': 'pure visibility predicate, not a component',

  // lib/widgets/recording_behavior.dart — pure code→string mappings, a pure
  // gate predicate, and call sites that pour recording-specific content into
  // the already-prefixed WpToast.
  'localizeRecordingError': 'code→string mapping, not a component',
  'localizeRecordingInfo': 'code→string mapping, not a component',
  'shouldShowCpuFallbackToast': 'pure gate predicate, not a component',
  'showRecordingErrorToast': 'call site of WpToast, not a component',
  'showPasteFailureToast': 'call site of WpToast, not a component',
  'showRecoveryToast': 'call site of WpToast, not a component',
  'showCpuFallbackToast': 'call site of WpToast, not a component',

  // lib/widgets/feature_spotlight_notice.dart — call site of the existing
  // _FeatureSpotlightDialog component, not a component of its own.
  'showFeatureSpotlightPreview':
      'call site of _FeatureSpotlightDialog, not a component',

  // Test seams — not public component API.
  'platformIsWindowsOverride': '@visibleForTesting seam',
  'storeThankYouPlatformIsWindowsOverride': '@visibleForTesting seam',
};

/// Matches a top-level type declaration at column 0, with any leading
/// class modifiers (`abstract`, `final`, `base`, `interface`, `sealed`, …).
final _typeDeclaration = RegExp(
  r'^(?:(?:abstract|final|base|interface|sealed|mixin)\s+)*'
  r'(class|enum|mixin|extension|typedef)\s+'
  r'([A-Za-z_$][A-Za-z0-9_$]*)',
);

/// Matches a top-level `show…` function declaration at column 0, e.g.
/// `Future<bool> showWpConfirmDialog({` or `void showCpuFallbackToast({`.
final _showFunctionDeclaration = RegExp(
  r'^[A-Za-z_$][A-Za-z0-9_$<>?,\s]*\s(show[A-Z][A-Za-z0-9_$]*)\s*[<(]',
);

List<File> _widgetSources() {
  final dir = Directory('lib/widgets');
  expect(
    dir.existsSync(),
    isTrue,
    reason:
        'Run this test from the package root — lib/widgets/ was not found at '
        '${dir.absolute.path}',
  );
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('Wp prefix consistency in lib/widgets/', () {
    test('every public type carries the Wp prefix', () {
      final offenders = <String>[];

      for (final file in _widgetSources()) {
        for (final line in file.readAsLinesSync()) {
          final match = _typeDeclaration.firstMatch(line);
          if (match == null) continue;

          final name = match.group(2)!;
          if (name.startsWith('_')) continue; // private — not API
          if (name.startsWith('Wp')) continue;
          if (_documentedExceptions.containsKey(name)) continue;

          offenders.add('${file.path}: ${match.group(1)} $name');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Public types under lib/widgets/ belong to the shared component '
            'vocabulary and must start with "Wp". Either rename them, or — if '
            'one is genuinely not a component — document the reason at its '
            'declaration and mirror it in _documentedExceptions.\nOffenders:\n'
            '${offenders.join('\n')}',
      );
    });

    test('every public dialog/picker launcher uses the showWp* infix', () {
      final offenders = <String>[];

      for (final file in _widgetSources()) {
        for (final line in file.readAsLinesSync()) {
          if (line.startsWith('//') || line.startsWith('///')) continue;

          final match = _showFunctionDeclaration.firstMatch(line);
          if (match == null) continue;

          final name = match.group(1)!;
          if (name.startsWith('showWp')) continue;
          if (_documentedExceptions.containsKey(name)) continue;

          offenders.add('${file.path}: $name');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A function that launches a component defined in lib/widgets/ is '
            'that component\'s public API and takes the showWp* infix (see '
            'showWpConfirmDialog). A function that merely calls an existing '
            'Wp component with feature content is not — document that at its '
            'declaration and mirror it in _documentedExceptions.\nOffenders:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the exception list stays honest — no stale entries', () {
      final source = _widgetSources()
          .map((f) => f.readAsStringSync())
          .join('\n');

      final stale = _documentedExceptions.keys
          .where((name) => !RegExp('\\b$name\\b').hasMatch(source))
          .toList();

      expect(
        stale,
        isEmpty,
        reason:
            'These symbols no longer exist under lib/widgets/ — drop them from '
            '_documentedExceptions so the list keeps describing reality:\n'
            '${stale.join('\n')}',
      );
    });
  });
}
