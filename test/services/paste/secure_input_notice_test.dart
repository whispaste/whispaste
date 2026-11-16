// Notice wording for macOS secure input (F35-8, #1617): who holds the
// keyboard decides the cause sentence. A macOS password prompt is answered or
// closed, never quit; Terminal and iTerm2 name their menu switch; another app
// is named; without a holder the text names no app. Every skipped-paste text
// ends with the clipboard sentence.
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
const _securityAgent = SecureInputHolder(
  name: 'SecurityAgent',
  bundleId: 'com.apple.SecurityAgent',
);
const _loginwindow = SecureInputHolder(
  name: 'loginwindow',
  bundleId: 'com.apple.loginwindow',
);

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

  group('classifySecureInputHolder', () {
    test('SecurityAgent and loginwindow are macOS password prompts', () {
      expect(
        classifySecureInputHolder(_securityAgent),
        SecureInputHolderKind.systemPrompt,
      );
      expect(
        classifySecureInputHolder(_loginwindow),
        SecureInputHolderKind.systemPrompt,
      );
    });

    test('a system prompt is known by its bundle id alone', () {
      expect(
        classifySecureInputHolder(
          const SecureInputHolder(bundleId: 'com.apple.SecurityAgent'),
        ),
        SecureInputHolderKind.systemPrompt,
      );
    });

    test('a system prompt is known by its process name alone', () {
      expect(
        classifySecureInputHolder(
          const SecureInputHolder(name: 'SecurityAgent'),
        ),
        SecureInputHolderKind.systemPrompt,
      );
      expect(
        classifySecureInputHolder(const SecureInputHolder(name: 'loginwindow')),
        SecureInputHolderKind.systemPrompt,
      );
    });

    test('Terminal and iTerm2 by bundle id', () {
      expect(
        classifySecureInputHolder(_terminal),
        SecureInputHolderKind.terminal,
      );
      expect(
        classifySecureInputHolder(
          const SecureInputHolder(bundleId: 'com.apple.Terminal'),
        ),
        SecureInputHolderKind.terminal,
      );
      expect(classifySecureInputHolder(_iterm), SecureInputHolderKind.iterm);
    });

    test('another named app, and nothing known', () {
      expect(classifySecureInputHolder(_zoom), SecureInputHolderKind.app);
      expect(classifySecureInputHolder(null), SecureInputHolderKind.unknown);
      expect(
        classifySecureInputHolder(const SecureInputHolder()),
        SecureInputHolderKind.unknown,
      );
      expect(
        classifySecureInputHolder(
          const SecureInputHolder(bundleId: 'us.zoom.xos'),
        ),
        SecureInputHolderKind.unknown,
        reason: 'without a name there is nothing to call the app',
      );
    });
  });

  group('secureInputAppLabel', () {
    test('keeps a usual name whole, trimmed', () {
      expect(secureInputAppLabel(' Microsoft Outlook '), 'Microsoft Outlook');
    });

    test('cuts a long name with an ellipsis to the maximum', () {
      final label = secureInputAppLabel('Google Chrome Canary Build');
      expect(label, endsWith('…'));
      expect(label.length, lessThanOrEqualTo(kSecureInputAppNameMax));
      expect(label, startsWith('Google Chrome'));
    });
  });

  group('secureInputNoticeBody', () {
    test('a macOS password prompt gets its own text, never "quit"', () {
      for (final holder in [_securityAgent, _loginwindow]) {
        final body = _body(en, holder);
        expect(body, startsWith(en.pasteSecureInputSystem));
        expect(body, isNot(contains(holder.name!)));
        expect(_body(de, holder), startsWith(de.pasteSecureInputSystem));
        expect(_body(de, holder), isNot(contains('beende')));
      }
    });

    test('names another app that holds the keyboard', () {
      expect(_body(en, _zoom), startsWith(en.pasteSecureInputNamed('Zoom')));
    });

    test('Terminal and iTerm2 name their menu switch', () {
      expect(_body(en, _terminal), startsWith(en.pasteSecureInputTerminal));
      expect(_body(en, _iterm), startsWith(en.pasteSecureInputIterm));
    });

    test('without a holder the generic text names no app', () {
      final body = _body(en, null);
      expect(body, startsWith(en.pasteSecureInputGeneric));
      expect(_body(en, const SecureInputHolder()), body);
    });

    test('always ends with the clipboard sentence and Cmd+V', () {
      for (final l10n in [en, de]) {
        for (final holder in [
          _securityAgent,
          _loginwindow,
          _terminal,
          _iterm,
          _zoom,
          null,
        ]) {
          expect(
            _body(l10n, holder),
            endsWith(l10n.pasteSecureInputClipboard(_shortcut(l10n))),
            reason: '${l10n.localeName} holder: ${holder?.name}',
          );
        }
      }
      expect(_body(en, _zoom), contains('⌘V'));
    });

    test('secureInputNotice pairs the short title with the body', () {
      final text = secureInputNotice(
        de,
        shortcut: _shortcut(de),
        holder: _securityAgent,
      );
      expect(text.title, de.pasteSecureInputTitle);
      expect(text.body, _body(de, _securityAgent));
    });
  });

  group('pasteResultNotice for secureInput', () {
    test('is an OS warning with the short title and the full body', () {
      final notice = pasteResultNotice(
        outcome: PasteOutcome.secureInput,
        l10n: en,
        platform: TargetPlatform.macOS,
        secureInputHolder: _securityAgent,
      )!;

      expect(notice.kind, AttentionKind.pasteFailedUnknown);
      expect(notice.title, en.pasteSecureInputTitle);
      expect(notice.body, _body(en, _securityAgent));
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
