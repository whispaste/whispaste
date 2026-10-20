/// openExternalUrl reports a failed launch instead of failing silently
/// (UIA-HLP-01, UIA-FBK-08, UIA-SET-09).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/external_link.dart';

import '../fixtures/test_helpers.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
const _url = 'https://example.org/datenschutz';

Widget _host() => makeTestable(
  Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => openExternalUrl(context, _url),
        child: const Text('open'),
      ),
    ),
  ),
  locale: const Locale('de'),
);

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null),
  );

  testWidgets('a failed launch shows a toast with a copy-address action', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch') return false;
          return false;
        });
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Link konnte nicht geöffnet werden'), findsOneWidget);
    expect(find.text('Adresse kopieren'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });

  testWidgets('a successful launch shows no toast', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async => true);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Link konnte nicht geöffnet werden'), findsNothing);
  });
}
