import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `manual*` ARB keys that the chapter list deliberately does not render (they
/// belong to the manual screen or the About entry), with the reason.
const _unrenderedManualKeys = <String, String>{
  'manualNoticeLabel':
      'Screen chrome: the label of notice blocks rendered by user_manual_view.dart.',
  'manualSearchHint':
      'Screen chrome: the search field placeholder in user_manual_view.dart.',
  'manualSearchResultCount':
      'Screen chrome: the live match count under the search field in user_manual_view.dart.',
  'manualSearchEmpty':
      'Screen chrome: the empty-search message in user_manual_view.dart.',
  'manualCodeCopy':
      'Screen chrome: the copy button of code blocks in user_manual_view.dart.',
  'manualCodeCopied':
      'Screen chrome: the copied confirmation of code blocks in user_manual_view.dart.',
  'manualCodeCopyFailed':
      'Screen chrome: the failed-copy notice of code blocks in user_manual_view.dart.',
};

void main() {
  test('every manual ARB key is rendered by manual_chapters.dart or '
      'allowlisted', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final chapters = File(
      'lib/features/help/manual/manual_chapters.dart',
    ).readAsStringSync();
    final missing = <String>[
      for (final key in arb.keys)
        if (key.startsWith('manual') &&
            !_unrenderedManualKeys.containsKey(key) &&
            !RegExp('\\bl\\.${RegExp.escape(key)}\\b').hasMatch(chapters))
          key,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'Add these to manual_chapters.dart, or allowlist them with a reason: '
          '${missing.join(', ')}',
    );
  });

  test('allowlisted manual keys still exist in app_en.arb', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      _unrenderedManualKeys.keys.where((k) => !arb.containsKey(k)),
      isEmpty,
    );
  });
}
