// Notice wording for an auto-paste skipped because macOS secure input is on
// (F35-8). The holder name and the Terminal/iTerm2 tips come from the native
// lookup; without a holder the generic notice names no app.
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/paste/paste_result_notice.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/paste/secure_input_notice.dart';
import 'package:whispaste/services/system_attention_service.dart';

const _terminal = SecureInputHolder(
  name: 'Terminal',
  bundleId: 'com.apple.Terminal',
);
const _iterm = SecureInputHolder(
  name: 'iTerm2',
  bundleId: 'com.googlecode.iterm2',
);
const _zoom = SecureInputHolder(name: 'Zoom', bundleId: 'us.zoom.xos');

late L10n en;
late L10n de;

String _shortcut(L10n l10n) => pasteShortcutLabel(l10n: l10n, isMacOS: true);

String _body(L10n l10n, SecureInputHolder? holder) =>
    secureInputNoticeBody(l10n, shortcut: _shortcut(l10n), holder: holder);

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
    de = await L10n.delegate.load(const Locale('de'));
  });

  group('secureInputNoticeBody', () {
    test('names the app that holds secure input and the way out', () {
      final body = _body(en, _zoom);

      expect(body, contains(en.pasteSecureInputNamed('Zoom')));
      expect(body, contains('Zoom'));
    });

    test('always says the text is on the clipboard and names Cmd+V', () {
      for (final holder in [_zoom, _terminal, _iterm, null]) {
        expect(
          _body(en, holder),
          contains(en.pasteSecureInputClipboard(_shortcut(en))),
          reason: 'holder: ${holder?.name}',
        );
      }
      expect(_body(en, _zoom), contains('⌘V'));
    });

    test('Terminal holder gets the Terminal tip', () {
      final body = _body(en, _terminal);

      expect(body, contains(en.pasteSecureInputTerminalTip));
      expect(body, isNot(contains(en.pasteSecureInputItermTip)));
    });

    test('Terminal tip also shows when only the bundle id is known', () {
      final body = _body(
        en,
        const SecureInputHolder(bundleId: 'com.apple.Terminal'),
      );

      expect(body, contains(en.pasteSecureInputTerminalTip));
      expect(body, contains(en.pasteSecureInputGeneric));
    });

    test('iTerm2 holder gets its own tip, not the Terminal one', () {
      final body = _body(en, _iterm);

      expect(body, contains(en.pasteSecureInputItermTip));
      expect(body, isNot(contains(en.pasteSecureInputTerminalTip)));
    });

    test('another app gets neither tip', () {
      final body = _body(
        en,
        const SecureInputHolder(name: 'Safari', bundleId: 'com.apple.Safari'),
      );

      expect(body, isNot(contains(en.pasteSecureInputTerminalTip)));
      expect(body, isNot(contains(en.pasteSecureInputItermTip)));
    });

    test('without a holder the generic notice names no app', () {
      final body = _body(en, null);

      expect(body, contains(en.pasteSecureInputGeneric));
      expect(body, isNot(contains('Zoom')));
      expect(body, isNot(contains('Terminal')));
    });

    test('a holder without name or bundle id reads like no holder', () {
      expect(_body(en, const SecureInputHolder()), _body(en, null));
    });

    test('the German wording names the app in the German sentence', () {
      final body = _body(de, _zoom);

      expect(body, contains(de.pasteSecureInputNamed('Zoom')));
      expect(body, contains(de.pasteSecureInputClipboard(_shortcut(de))));
      expect(_body(de, _terminal), contains(de.pasteSecureInputTerminalTip));
    });
  });

  group('pasteResultNotice for secureInput', () {
    test('is an OS warning with the body of secureInputNoticeBody', () {
      final notice = pasteResultNotice(
        outcome: PasteOutcome.secureInput,
        l10n: en,
        platform: TargetPlatform.macOS,
        secureInputHolder: _zoom,
      )!;

      expect(notice.kind, AttentionKind.pasteFailedUnknown);
      expect(notice.title, en.pasteNotificationFailedTitle);
      expect(notice.body, _body(en, _zoom));
      expect(notice.informational, isFalse);
      expect(notice.trayLabel, isNull, reason: 'the text is safe, no badge');
      expect(notice.action, isNull);
    });

    test('without a holder it uses the generic body', () {
      final notice = pasteResultNotice(
        outcome: PasteOutcome.secureInput,
        l10n: en,
        platform: TargetPlatform.macOS,
      )!;

      expect(notice.body, _body(en, null));
    });
  });
}
