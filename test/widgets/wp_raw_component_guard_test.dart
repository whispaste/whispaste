import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static gate for the component drift of #1757: icon buttons go through
/// `WpIconButton` (its tooltip becomes the accessible *label*, a raw
/// `IconButton(tooltip:)` only publishes a hint), and action menus through
/// `showWpListMenu` or `showWpContextMenu`. Each allowlisted file says in
/// the code why it is an exception.
void main() {
  const allowed = <String, Set<String>>{
    // The clear control inside the field decoration (see its comment).
    'IconButton': {'lib/widgets/wp_search_field.dart'},
    'PopupMenuButton': {
      // Design-system menus with their own row/slot geometry.
      'lib/widgets/wp_multi_select_bar.dart',
      'lib/widgets/wp_head_actions.dart',
    },
    'showMenu': {
      // The two shared menu helpers themselves.
      'lib/widgets/searchable_list_page.dart',
      'lib/widgets/wp_context_menu.dart',
    },
  };
  final patterns = <String, RegExp>{
    'IconButton': RegExp(r'(?<![\w.])IconButton(\.\w+)?\('),
    'PopupMenuButton': RegExp(r'\bPopupMenuButton(<[^>]*>)?\('),
    'showMenu': RegExp(r'\bshowMenu(<[^>]*>)?\('),
  };

  for (final MapEntry(key: name, value: pattern) in patterns.entries) {
    test('no raw $name outside the design system', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relPath = entity.path.replaceAll(r'\', '/');
        if (allowed[name]!.contains(relPath)) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          // IconButton.styleFrom only styles, it builds no button.
          if (code.contains('IconButton.styleFrom')) continue;
          if (pattern.hasMatch(code)) offenders.add('$relPath:${i + 1}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Raw $name found: use WpIconButton / showWpListMenu / '
            'showWpContextMenu, or justify the exception in the code and '
            'allowlist it here: ${offenders.join(', ')}',
      );
    });
  }
}
