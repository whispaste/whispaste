/// openExternalUrl reports a failed launch instead of failing silently
/// (UIA-HLP-01, UIA-FBK-08, UIA-SET-09).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/external_link.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../fixtures/test_helpers.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
const _url = 'https://example.org/datenschutz';

Widget _host() => makeTestable(
  Builder(
    builder: (context) => Column(
      children: [
        const WpAppErrorSlot(),
        TextButton(
          onPressed: () => openExternalUrl(context, _url),
          child: const Text('open'),
        ),
      ],
    ),
  ),
  locale: const Locale('de'),
);

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null),
  );

  testWidgets(
    'a failed launch leaves a notice that stays, with a copy-address action',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcherChannel, (call) async {
            if (call.method == 'canLaunch') return false;
            return false;
          });
      await tester.pumpWidget(_host());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('page-notice-external-link-failed')),
        findsOneWidget,
      );
      expect(find.text('Adresse kopieren'), findsOneWidget);
      // An error never closes itself.
      await tester.pump(const Duration(seconds: 60));
      expect(
        find.byKey(const ValueKey('page-notice-external-link-failed')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a successful launch shows no notice', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async => true);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-notice-external-link-failed')),
      findsNothing,
    );
  });
}
