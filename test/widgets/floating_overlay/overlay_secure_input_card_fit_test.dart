// #1617: the overlay card for a paste that macOS secure input skipped shows
// its whole message at the default text size: the outcome as a one-line
// headline, and cause, way out and clipboard sentence in the body without an
// ellipsis. A text that does not fit has to get shorter, not cut.
//
// Measured with the bundled Inter, the card's own font. Hebrew has no
// bundled font (the test font would draw every glyph as a wide box), so its
// texts are held to the length of the English ones that are measured.
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice_rules.dart';
import 'package:whispaste/services/paste/secure_input_notice.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

/// One holder of every kind. The app name is longer than
/// [kSecureInputAppNameMax], so the text quotes it at the longest it gets.
const _holders = <String, SecureInputHolder?>{
  'system prompt': SecureInputHolder(
    name: 'SecurityAgent',
    bundleId: 'com.apple.SecurityAgent',
  ),
  'Terminal': SecureInputHolder(
    name: 'Terminal',
    bundleId: 'com.apple.Terminal',
  ),
  'iTerm2': SecureInputHolder(
    name: 'iTerm2',
    bundleId: 'com.googlecode.iterm2',
  ),
  'named app': SecureInputHolder(
    name: 'Google Chrome Canary Build',
    bundleId: 'com.google.Chrome.canary',
  ),
  'unknown': null,
};

const _measured = ['de', 'en', 'es', 'pt', 'ru'];

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final file in ['Inter-Regular.ttf', 'Inter-SemiBold.ttf']) {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The card as the overlay shows it for the skipped paste: no buttons, the
/// close cross and the key footer of a card with no dictation behind it.
OverlayNotice _card(L10n l10n, SecureInputHolder? holder) {
  final text = secureInputNotice(
    l10n,
    shortcut: pasteShortcutLabel(l10n: l10n, isMacOS: true),
    holder: holder,
  );
  return overlayNoticeFor(
    DictationNotice(
      id: 'paste-secure-input',
      cause: text.title,
      nextStep: text.body,
      offersNewDictation: false,
    ),
    l10n,
  ).withFooter(
    noticeFooterFor(
      l10n: l10n,
      phase: NoticeFooterPhase.idle,
      hotkey: 'Fn',
      cancelKey: 'Esc',
    ),
  );
}

void main() {
  setUpAll(_loadInter);

  test('the headline is the short outcome and the body ends with the '
      'clipboard sentence', () async {
    final l10n = await L10n.delegate.load(const Locale('de'));
    final card = _card(l10n, _holders['system prompt']);
    expect(card.title, l10n.pasteSecureInputTitle);
    expect(card.body, endsWith(l10n.pasteSecureInputClipboard('⌘V')));
    expect(overlayNoticeTitleMaxLines(card), 1);
    expect(
      overlayNoticeBodyMaxLines(card),
      3,
      reason: 'a card without buttons has room for a third body line',
    );
  });

  for (final lang in _measured) {
    for (final MapEntry(key: kind, value: holder) in _holders.entries) {
      testWidgets('$lang, $kind: headline and body fit uncut', (tester) async {
        final l10n = await L10n.delegate.load(Locale(lang));
        final card = _card(l10n, holder);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Center(
                child: WpOverlayNoticeCard(
                  notice: card,
                  colors: OverlayDesignSpec.colorsFor(),
                ),
              ),
            ),
          ),
        );
        for (final text in [card.title, card.body]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        }
      });
    }
  }

  test('Hebrew texts are no longer than the measured English ones', () async {
    final he = await L10n.delegate.load(const Locale('he'));
    final en = await L10n.delegate.load(const Locale('en'));
    for (final MapEntry(key: kind, value: holder) in _holders.entries) {
      final heCard = _card(he, holder);
      final enCard = _card(en, holder);
      expect(
        heCard.body.length,
        lessThanOrEqualTo(enCard.body.length),
        reason: kind,
      );
      expect(heCard.title.length, lessThanOrEqualTo(enCard.title.length));
    }
  });
}
