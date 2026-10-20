import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/ltr_isolate.dart';

/// Hebrew strings embed LTR fragments (URLs, paths, `|`) as placeholders.
/// The call sites wrap each value with ltrIsolate (LRI/PDI), and the ARB
/// files stay free of raw bidi code points.
final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

void main() {
  final he = lookupL10n(const Locale('he'));

  test('ltrIsolate wraps a fragment in LRI/PDI', () {
    expect(ltrIsolate('|'), '$_lri|$_pdi');
  });

  test('he hook URL help isolates each URL', () {
    final text = he.automationHooksInvalidUrl(
      ltrIsolate('http://127.0.0.1'),
      ltrIsolate('http://[::1]'),
      ltrIsolate('http://localhost'),
      ltrIsolate('http://127.0.0.1:9000/hook'),
    );
    expect(
      text,
      contains(
        '$_lri'
        'http://127.0.0.1$_pdi',
      ),
    );
    expect(
      text,
      contains(
        '$_lri'
        'http://[::1]$_pdi',
      ),
    );
  });

  test('he CLI subtitle isolates path, token and command', () {
    final text = he.automationIntegrationsCliSubtitle(
      ltrIsolate('tool/whispaste.dart'),
      ltrIsolate('WHISPASTE_API_TOKEN'),
      ltrIsolate('mcp'),
    );
    expect(
      text,
      contains(
        '$_lri'
        'tool/whispaste.dart$_pdi',
      ),
    );
    expect(
      text,
      contains(
        '$_lri'
        'WHISPASTE_API_TOKEN$_pdi',
      ),
    );
  });

  test('he CSV hint isolates the trigger separator', () {
    expect(he.dictionaryCsvHint(ltrIsolate('|')), contains('$_lri|$_pdi'));
  });

  testWidgets('he hook URL help renders under he locale without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Builder(
              builder: (context) => Text(
                L10n.of(context).automationHooksInvalidUrl(
                  ltrIsolate('http://127.0.0.1'),
                  ltrIsolate('http://[::1]'),
                  ltrIsolate('http://localhost'),
                  ltrIsolate('http://127.0.0.1:9000/hook'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('127.0.0.1'), findsOneWidget);
  });
}
