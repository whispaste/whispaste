import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/profiles/profiles_section.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/app_profiles/app_target_capture.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../../fixtures/fake_app_profiles.dart';
import '../../../fixtures/record_device_listing_stub.dart';
import '../../../fixtures/test_helpers.dart';

const _mail = AppProfile(
  id: 'a',
  name: 'Mail',
  modelId: 'whisper:whisper-small',
  hotkeyKey: 'F5',
  hotkeyModifiers: 'ctrl+shift',
);
const _notes = AppProfile(id: 'b', name: 'Notizen');

Future<L10n> _en() => L10n.delegate.load(const Locale('en'));

/// The label of a button, not a text elsewhere that happens to match it.
Finder _button(String label) =>
    find.descendant(of: find.byType(WpButton), matching: find.text(label));

Future<FakeAppProfiles> _pump(
  WidgetTester tester,
  List<AppProfile> profiles, {
  Future<AppCaptureOutcome> Function()? capture,
}) async {
  final fake = FakeAppProfiles(profiles);
  // Tall enough that every row is on screen, so taps land without scrolling.
  tester.view.physicalSize = const Size(1280, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: ProfilesSection()),
      locale: const Locale('en'),
      size: const Size(1280, 1600),
      overrides: [
        appProfilesProvider.overrideWith(() => fake),
        settingsProvider.overrideWith(FakeSettings.new),
        modelDownloadProvider.overrideWith(FakeModelDownloads.new),
        audioInputDevicesProvider.overrideWith((ref) async => <String>[]),
        if (capture != null) appCaptureProvider.overrideWithValue(capture),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubRecordDeviceListing();
  });

  group('list', () {
    testWidgets('an empty list explains itself and creates the first profile', (
      tester,
    ) async {
      final l10n = await _en();
      final fake = await _pump(tester, const []);

      expect(find.text(l10n.profilesEmptyBody), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profiles-add-first')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'Neu');
      await tester.tap(find.byKey(const ValueKey('profiles-create-confirm')));
      await tester.pumpAndSettle();

      expect(fake.saves.single.name, 'Neu');
      expect(fake.saves.single.rules, isEmpty);
    });

    testWidgets('a blank name is refused in the create dialog', (tester) async {
      final l10n = await _en();
      final fake = await _pump(tester, const []);

      await tester.tap(find.byKey(const ValueKey('profiles-add-first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profiles-create-confirm')));
      await tester.pumpAndSettle();

      expect(fake.saves, isEmpty);
      expect(find.text(l10n.profilesNameEmpty), findsOneWidget);
    });

    testWidgets('renaming in the detail saves the new name', (tester) async {
      final fake = await _pump(tester, const [_mail]);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('profile-detail-name')),
          matching: find.byType(EditableText),
        ),
        'Post',
      );
      await tester.pump();

      expect(fake.saves.last.name, 'Post');
      expect(fake.saves.last.id, 'a');
    });

    testWidgets('deleting asks first, then removes the profile', (
      tester,
    ) async {
      final l10n = await _en();
      final fake = await _pump(tester, const [_mail, _notes]);

      await tester.tap(find.byKey(const ValueKey('profile-detail-delete')));
      await tester.pumpAndSettle();
      expect(fake.deletes, isEmpty);

      await tester.tap(_button(l10n.profileDeleteAction).last);
      await tester.pumpAndSettle();

      expect(fake.deletes, ['a']);
    });
  });

  group('sorting', () {
    testWidgets('the move buttons swap neighbours and cannot leave the list', (
      tester,
    ) async {
      final fake = await _pump(tester, const [_mail, _notes]);

      await tester.tap(find.byKey(const ValueKey('profiles-move-up-a')));
      await tester.pumpAndSettle();
      expect(fake.reorders, isEmpty, reason: 'the first one cannot move up');

      await tester.tap(find.byKey(const ValueKey('profiles-move-down-a')));
      await tester.pumpAndSettle();
      expect(fake.reorders.single, ['b', 'a']);
    });

    testWidgets('dragging the handle reorders the list', (tester) async {
      final fake = await _pump(tester, const [_mail, _notes]);

      await tester.drag(
        find.byKey(const ValueKey('profiles-drag-a')),
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();

      expect(fake.reorders, isNotEmpty);
      expect(fake.reorders.last, ['b', 'a']);
    });
  });

  group('fields', () {
    testWidgets('"Unverändert lassen" is saved as null, not as a value', (
      tester,
    ) async {
      final l10n = await _en();
      final fake = await _pump(tester, const [_mail]);

      await tester.tap(find.byKey(const ValueKey('profile-detail-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileKeepUnchanged).last);
      await tester.pumpAndSettle();

      expect(fake.saves.last.modelId, isNull);
    });

    testWidgets('a hotkey held by a later profile shows the conflict', (
      tester,
    ) async {
      final l10n = await _en();
      const clash = AppProfile(
        id: 'b',
        name: 'Notizen',
        hotkeyKey: 'F5',
        hotkeyModifiers: 'ctrl+shift',
      );
      await _pump(tester, const [_mail, clash]);

      await tester.tap(find.byKey(const ValueKey('profiles-select-b')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile-detail-hotkey-notice')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.profileHotkeyTakenByProfile('Mail')),
        findsOneWidget,
      );
    });

    testWidgets('the first profile keeps its hotkey without a notice', (
      tester,
    ) async {
      const clash = AppProfile(
        id: 'b',
        name: 'Notizen',
        hotkeyKey: 'F5',
        hotkeyModifiers: 'ctrl+shift',
      );
      await _pump(tester, const [_mail, clash]);

      expect(
        find.byKey(const Key('profile-detail-hotkey-notice')),
        findsNothing,
      );
    });
  });

  group('target apps', () {
    testWidgets('adding and removing a rule saves the rule list', (
      tester,
    ) async {
      final fake = await _pump(tester, const [_mail]);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('profile-detail-apps-input')),
          matching: find.byType(EditableText),
        ),
        'com.example.app',
      );
      await tester.tap(find.byKey(const ValueKey('profile-detail-app-add')));
      await tester.pumpAndSettle();

      expect(fake.saves.last.rules.map((r) => r.identifier), [
        'com.example.app',
      ]);

      await tester.tap(
        find.byKey(const ValueKey('profile-detail-app-remove-com.example.app')),
      );
      await tester.pumpAndSettle();

      expect(fake.saves.last.rules, isEmpty);
    });

    testWidgets('an app another profile claims is refused with its name', (
      tester,
    ) async {
      final l10n = await _en();
      const withRule = AppProfile(
        id: 'b',
        name: 'Notizen',
        rules: [AppMatchRule(identifier: 'com.example.app')],
      );
      final fake = await _pump(tester, const [_mail, withRule]);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('profile-detail-apps-input')),
          matching: find.byType(EditableText),
        ),
        'com.example.app',
      );
      await tester.tap(find.byKey(const ValueKey('profile-detail-app-add')));
      await tester.pumpAndSettle();

      expect(fake.saves, isEmpty);
      expect(find.text(l10n.profileAppClash('Notizen')), findsOneWidget);
    });

    testWidgets('"App erfassen" counts down, then adds the app in front', (
      tester,
    ) async {
      final fake = await _pump(tester, const [
        _mail,
      ], capture: () async => const AppCaptured('com.example.app'));

      await tester.tap(
        find.byKey(const ValueKey('profile-detail-app-capture')),
      );
      await tester.pump();
      expect(fake.saves, isEmpty, reason: 'nothing is read during countdown');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(fake.saves.last.rules.map((r) => r.identifier), [
        'com.example.app',
      ]);
    });

    testWidgets('no other app in front shows a hint and adds nothing', (
      tester,
    ) async {
      final l10n = await _en();
      final fake = await _pump(tester, const [
        _mail,
      ], capture: () async => const AppCaptureNoForeignApp());

      await tester.tap(
        find.byKey(const ValueKey('profile-detail-app-capture')),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(fake.saves, isEmpty);
      expect(find.text(l10n.profileAppCaptureNone), findsOneWidget);
    });

    testWidgets('a platform without capture shows the manual fallback hint', (
      tester,
    ) async {
      final l10n = await _en();
      await _pump(tester, const [
        _mail,
      ], capture: () async => const AppCaptureUnavailable());

      await tester.tap(
        find.byKey(const ValueKey('profile-detail-app-capture')),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text(l10n.profileAppCaptureUnavailable), findsOneWidget);
      expect(find.textContaining(l10n.profileAppHintLinux), findsOneWidget);
    });
  });

  group('limit', () {
    testWidgets('nine profiles disable adding and show the limit', (
      tester,
    ) async {
      final l10n = await _en();
      final nine = [
        for (var i = 0; i < 9; i++) AppProfile(id: 'p$i', name: 'P$i'),
      ];
      final fake = await _pump(tester, nine);

      expect(find.byKey(const ValueKey('profiles-limit-note')), findsOneWidget);
      expect(find.text(l10n.profilesLimitReached), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(WpButton),
          matching: find.text(l10n.profilesAdd),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.profilesNewTitle), findsNothing);
      expect(fake.saves, isEmpty);
    });
  });
}
