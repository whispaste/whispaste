/// The hotkey notices of the overlay fit their card in every app language
/// (#1845): instruction and button labels are read in full, never cut by an
/// ellipsis. The card grows with its content instead (#1845): the footer
/// wraps at the small type step and buttons that do not fit side by side
/// stack.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/hotkey_hint_notices.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

import '../../fixtures/app_fonts.dart';

T _noRead<T>(ProviderListenable<T> provider) =>
    throw UnimplementedError('not pressed in this test');

void main() {
  setUpAll(loadAppFontsOnce);

  final notices = <String, DictationNotice Function(L10n)>{
    'short press': (l) => shortPressHintNotice(l, _noRead),
    'input monitoring': (l) => inputMonitoringOfferNotice(l, _noRead),
    'no favorite languages': (l) => noFavoriteLanguagesNotice(l, _noRead),
  };

  for (final locale in L10n.supportedLocales) {
    for (final MapEntry(key: name, value: build) in notices.entries) {
      testWidgets('$name notice fits the card in ${locale.languageCode}', (
        tester,
      ) async {
        final l10n = await L10n.delegate.load(locale);
        final notice = overlayNoticeFor(build(l10n), l10n, actionKey: 'F12');
        await tester.pumpWidget(
          Directionality(
            textDirection: locale.languageCode == 'he'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Center(
                child: WpOverlayNoticeCard(
                  notice: notice,
                  colors: OverlayDesignSpec.colorsFor(),
                ),
              ),
            ),
          ),
        );
        final cut = [
          for (final p in tester.renderObjectList<RenderParagraph>(
            find.byType(RichText),
          ))
            if (p.didExceedMaxLines) p.text.toPlainText(),
        ];
        expect(cut, isEmpty, reason: 'texts cut on the card');
      });
    }
  }

  testWidgets('German labels stay whole and the footer keeps the small step', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('de'));
    for (final notice in [
      for (final build in notices.values)
        overlayNoticeFor(build(l10n), l10n, actionKey: 'F12'),
      // Two long German labels: too wide side by side, so they stack.
      const OverlayNotice(
        kind: OverlayNoticeKind.message,
        tone: OverlayNoticeTone.hint,
        title: 'Eingabeüberwachung erlauben',
        body: 'Damit Whispaste die Taste erkennt, braucht es die Freigabe.',
        footer: 'Esc schließt den Hinweis · Fn+F12 startet das Diktat erneut',
        actions: [
          OverlayNoticeAction(
            action: OverlayNoticeActionId.changeMicrophone,
            label: 'Systemeinstellungen öffnen',
            keyHint: 'Enter',
            primary: true,
          ),
          OverlayNoticeAction(
            action: OverlayNoticeActionId.keepRecording,
            label: 'Später erinnern',
            keyHint: 'Esc',
          ),
        ],
      ),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Center(
              child: WpOverlayNoticeCard(
                notice: notice,
                colors: OverlayDesignSpec.colorsFor(),
              ),
            ),
          ),
        ),
      );
      final paragraphs = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      );
      for (final p in paragraphs) {
        expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
      }
      final footer = find.byKey(const ValueKey('overlay-notice-footer'));
      if (notice.footer.isNotEmpty) {
        final style = tester.widget<Text>(footer).style!;
        expect(style.fontSize, greaterThanOrEqualTo(WpTypography.small));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
