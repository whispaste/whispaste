/// Source guards for the UI audit wave C (design foundations and components).
///
/// Each guard pins one audit finding to the place it was fixed, so a literal
/// value or a private copy of a shared widget cannot quietly come back.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue, reason: '$relPath must exist');
  return file.readAsStringSync();
}

void main() {
  test('UIA-FND-14: side panel has no literal transparent accent', () {
    expect(
      _read('lib/widgets/side_panel/side_panel_view.dart'),
      isNot(contains('0x006FDDF0')),
    );
  });

  test('UIA-FND-11: animation literals moved onto WpMotion stages', () {
    const literalByPath = {
      'lib/widgets/toast.dart': 'Duration(milliseconds: 300)',
      'lib/features/settings/settings_page.dart': 'Duration(milliseconds: 300)',
      'lib/widgets/wp_split_view.dart': 'Duration(milliseconds: 150)',
      'lib/features/settings/widgets/settings_search_field.dart':
          'Duration(milliseconds: 120)',
    };
    literalByPath.forEach((path, literal) {
      expect(_read(path), isNot(contains(literal)), reason: path);
    });
  });

  test('UIA-FND-12: tooltip waits share WpMotion.tooltipWait', () {
    expect(_read('lib/core/theme/tokens.dart'), contains('tooltipWait'));
    for (final path in [
      'lib/widgets/sidebar.dart',
      'lib/widgets/markdown_toolbar.dart',
      'lib/widgets/find_replace_bar.dart',
      'lib/features/history/widgets/history_detail_panel.dart',
    ]) {
      final source = _read(path);
      expect(
        RegExp(
          r'waitDuration: (const )?Duration\(milliseconds: \d+\)',
        ).hasMatch(source),
        isFalse,
        reason: '$path must use WpMotion.tooltipWait, not a literal',
      );
    }
  });

  test('UIA-CMP-06: snippets and replacements use WpSegmentedSelector', () {
    for (final path in [
      'lib/features/snippets/snippets_page.dart',
      'lib/features/replacements/replacements_page.dart',
    ]) {
      expect(_read(path), isNot(contains('SegmentedButton')), reason: path);
    }
  });

  test('UIA-CMP-08: note editor toolbar uses WpIconButton, two exceptions', () {
    // The quick-note key and the pinned star are Font Awesome glyphs, which
    // WpIconButton (IconData only) cannot carry.
    final raw = RegExp(r'(?<!Wp)IconButton\(');
    expect(
      raw.allMatches(
        _read('lib/features/notes/widgets/note_editor_panel.dart'),
      ),
      hasLength(2),
    );
  });

  test('UIA-CMP-09: error notice is a WpBanner tone, not its own surface', () {
    expect(
      _read('lib/widgets/wp_error_notice.dart'),
      isNot(contains('errorActiveFill')),
    );
  });

  test('UIA-CMP-10: hotkey recorder uses WpKeycap, no private copy', () {
    expect(
      _read('lib/widgets/hotkey_recorder.dart'),
      isNot(contains('class _KeyCap')),
    );
  });

  test('UIA-ONB-15: onboarding steps use the radius and type helpers', () {
    final trigger = _read('lib/features/onboarding/steps/trigger_step.dart');
    expect(trigger, isNot(contains('BorderRadius.circular(WpRadius.sm)')));
    final appearance = _read(
      'lib/features/onboarding/steps/appearance_step.dart',
    );
    expect(appearance, isNot(contains('Theme.of(context).textTheme')));
  });

  test('UIA-FND-05: the fallback palette is the dark one', () {
    expect(
      _read('lib/core/theme/colors.dart'),
      contains('static WpThemeColors _active = wpDarkColors;'),
    );
  });

  test('UIA-FND-08: generated groups with no readers are gone', () {
    final generated = _read('lib/core/theme/generated/wp_tokens.g.dart');
    expect(generated, isNot(contains('class WpSpaceTokens')));
    expect(generated, isNot(contains('class WpDurationTokens')));
    expect(generated, isNot(contains('class WpEasingTokens')));
  });

  test('UIA-FND-13: resting rows use a control-edge border, no lift', () {
    final source = _read(
      'lib/widgets/wp_list_tile_surface.dart',
    ).replaceAll(RegExp(r'//.*$', multiLine: true), '');
    expect(source, isNot(contains('selectedLift')));
    expect(source, isNot(contains('WpShadows')));
    expect(
      'controlEdge'.allMatches(source).length,
      greaterThanOrEqualTo(3),
      reason: 'selected card, overview and panel edges',
    );
  });

  test(
    'UIA-FND-13: overlays share WpShadows.elevated, no resting shadow token',
    () {
      expect(_read('lib/widgets/toast.dart'), isNot(contains('BoxShadow(')));
      expect(
        _read('lib/widgets/toast.dart'),
        contains('boxShadow: WpShadows.elevated'),
      );
      for (final file in [
        'lib/features/settings/widgets/settings_search_field.dart',
        'lib/widgets/tag_input.dart',
      ]) {
        expect(_read(file), contains('WpShadows.elevated'), reason: file);
      }
      final tokens = _read('lib/core/theme/tokens.dart');
      expect(tokens, isNot(contains('static const List<BoxShadow> subtle')));
    },
  );
}
