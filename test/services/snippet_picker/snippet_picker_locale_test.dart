/// The picker engine is booted once per app session, so a language change
/// in the main window must reach it on the next show, footer included, not
/// only after a restart (#1680). Hand-off point: the locale mirror the main
/// engine writes → the `L10n` the picker body (and its footer) paints with.
/// Behaviour only: checks the resolved locale, no UI texts.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/persisted_locale.dart';
import 'package:whispaste/core/theme/persisted_appearance.dart';
import 'package:whispaste/snippet_picker_render_entrypoint.dart';

const _channel = 'com.whispaste.snippet_picker_render';

Future<void> _setItems(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel,
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('setItems', {
        'items': [
          {'id': 'a', 'title': 'Signature', 'body': 'Best'},
        ],
      }),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

String _bodyLocale(WidgetTester tester) => tester
    .widget<SnippetPickerBody>(find.byType(SnippetPickerBody))
    .l10n
    .localeName;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_picker_locale');
    localeMirrorPathOverride = '${dir.path}/locale';
    appearanceMirrorPathOverride = '${dir.path}/appearance';
  });

  tearDown(() {
    localeMirrorPathOverride = null;
    appearanceMirrorPathOverride = null;
    dir.deleteSync(recursive: true);
  });

  testWidgets('a language change reaches the open engine on the next show', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_channel),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(_channel),
        null,
      ),
    );

    writeLocaleMirror('en');
    await tester.pumpWidget(const SnippetPickerRenderApp());
    await _setItems(tester);
    expect(_bodyLocale(tester), 'en');

    // The user switches the app language; the engine stays alive.
    writeLocaleMirror('de');
    await _setItems(tester);
    expect(_bodyLocale(tester), 'de');
  });
}
