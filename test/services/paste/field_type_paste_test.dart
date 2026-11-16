import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/field_type_policy.dart';
import 'package:whispaste/services/paste/paster.dart';

import '../../test_helpers/probing_paste_controller.dart';

const _options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fieldTypeVerdict', () {
    test('password or PIN field means manual paste', () {
      expect(
        fieldTypeVerdict(FocusedFieldType.password),
        FieldTypeVerdict.manualPaste,
      );
    });

    test('normal and unknown fields paste as before', () {
      expect(fieldTypeVerdict(FocusedFieldType.normal), FieldTypeVerdict.paste);
      expect(
        fieldTypeVerdict(FocusedFieldType.unknown),
        FieldTypeVerdict.paste,
      );
    });

    test('wire codes map to types, anything else is unknown', () {
      expect(FocusedFieldType.fromCode('password'), FocusedFieldType.password);
      expect(FocusedFieldType.fromCode('normal'), FocusedFieldType.normal);
      expect(FocusedFieldType.fromCode('unknown'), FocusedFieldType.unknown);
      expect(FocusedFieldType.fromCode(null), FocusedFieldType.unknown);
      expect(FocusedFieldType.fromCode('secret'), FocusedFieldType.unknown);
    });
  });

  group('DesktopPaster field type (#948)', () {
    String? clipboardContent;
    setUp(() {
      clipboardContent = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardContent = (call.arguments as Map)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                if (clipboardContent == null) return null;
                return <String, dynamic>{'text': clipboardContent};
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test(
      'password field: no paste, transcript on the clipboard, passwordField',
      () async {
        final controller = ProbingPasteController(
          () async => FocusedFieldType.password,
        );
        final paster = DesktopPaster(controller);

        await paster.prime();
        final outcome = await paster.paste('secret words', _options);

        expect(outcome, PasteOutcome.passwordField);
        expect(controller.pasteCalls, 0);
        expect(controller.typeCalls, 0);
        expect(clipboardContent, 'secret words');
      },
    );

    test('password field also blocks the typing path', () async {
      final controller = ProbingPasteController(
        () async => FocusedFieldType.password,
      );
      final paster = DesktopPaster(controller);

      await paster.prime();
      final outcome = await paster.typeText('secret words', _options);

      expect(outcome, PasteOutcome.passwordField);
      expect(controller.typeCalls, 0);
      expect(controller.pasteCalls, 0);
    });

    test('normal and unknown fields paste as before', () async {
      for (final type in [FocusedFieldType.normal, FocusedFieldType.unknown]) {
        final controller = ProbingPasteController(() async => type);
        final paster = DesktopPaster(controller);

        await paster.prime();
        final outcome = await paster.paste('hello', _options);

        expect(outcome, isNot(PasteOutcome.passwordField), reason: '$type');
        expect(controller.pasteCalls, 1, reason: '$type');
      }
    });

    test('a failing probe pastes as before', () async {
      final controller = ProbingPasteController(
        () async => throw PlatformException(code: 'boom'),
      );
      final paster = DesktopPaster(controller);

      await paster.prime();
      final outcome = await paster.paste('hello', _options);

      expect(outcome, isNot(PasteOutcome.passwordField));
      expect(controller.pasteCalls, 1);
    });

    test('a hung probe falls back to pasting', () async {
      final controller = ProbingPasteController(
        () => Completer<FocusedFieldType>().future,
      );
      final paster = DesktopPaster(controller);

      await paster.prime();

      final outcome = await paster.paste('hello', _options);

      expect(outcome, isNot(PasteOutcome.passwordField));
      expect(controller.pasteCalls, 1);
    });

    test('without prime there is no probe and the paste runs', () async {
      final controller = ProbingPasteController(
        () async => FocusedFieldType.password,
      );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste('hello', _options);

      expect(controller.probeCalls, 0);
      expect(outcome, isNot(PasteOutcome.passwordField));
      expect(controller.pasteCalls, 1);
    });

    test('a probe answer is used by one paste only', () async {
      final controller = ProbingPasteController(
        () async => FocusedFieldType.password,
      );
      final paster = DesktopPaster(controller);

      await paster.prime();
      expect(await paster.paste('one', _options), PasteOutcome.passwordField);
      final second = await paster.paste('two', _options);

      expect(second, isNot(PasteOutcome.passwordField));
      expect(controller.pasteCalls, 1);
    });
  });
}
