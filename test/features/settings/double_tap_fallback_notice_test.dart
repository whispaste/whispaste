/// The notice under the hotkey row while a saved double tap cannot be observed
/// (PAR-056): each desktop OS names its own reason (macOS the missing Input
/// Monitoring permission, R18-2a Windows and Linux theirs), other systems keep
/// the generic wording.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

import '../../fixtures/record_device_listing_stub.dart';
import '../../fixtures/test_helpers.dart';

const _noticeKey = Key('mainHotkeyDoubleTapFallbackNotice');

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeDoubleTapFallback extends DoubleTapFallbackController {
  _FakeDoubleTapFallback(this._active);

  final bool _active;

  @override
  bool build() => _active;
}

// The shortcut row reads the hotkey service for key-up support, which would
// build the real service: its registration on a test host refuses the double
// tap and flips the fallback under the override. The notice must follow the
// override only.
class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

String _expectedNotice(L10n en) => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => en.settingsDoubleTapFallbackNoticeMac,
  TargetPlatform.windows => en.settingsDoubleTapFallbackNoticeWindows,
  TargetPlatform.linux => en.settingsDoubleTapFallbackNoticeLinux,
  _ => en.settingsDoubleTapFallbackNotice,
};

Widget _subject({required bool fallback, bool unavailable = false}) {
  final settings = AppSettings.defaults.copyWithSections(
    hotkey: AppSettings.defaults.hotkey.copyWith(
      hotkeyDoubleTapKey: ModifierHotkey.rightControl.name,
    ),
  );
  return makeTestable(
    const SingleChildScrollView(child: KeyboardShortcutSection()),
    locale: const Locale('en'),
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
      doubleTapFallbackActiveProvider.overrideWith(
        () => _FakeDoubleTapFallback(fallback),
      ),
      doubleTapUnavailableProvider.overrideWith(
        () => _FakeDoubleTapFallback(unavailable),
      ),
    ],
  );
}

void main() {
  stubRecordDeviceListing();

  late L10n en;

  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'names the reason of this OS while a saved double tap falls back',
    (tester) async {
      await tester.pumpWidget(_subject(fallback: true));
      await tester.pumpAndSettle();

      final notice = find.byKey(_noticeKey);
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text(_expectedNotice(en))),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a key this system cannot use reads as unavailable, and the row offers '
    'the combination that listens instead of the saved key',
    (tester) async {
      await tester.pumpWidget(_subject(fallback: true, unavailable: true));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(_noticeKey),
          matching: find.text(en.settingsDoubleTapUnavailableNotice),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mainHotkeyDoubleTapValue')), findsNothing);
      expect(find.byKey(const Key('mainHotkeyChange')), findsOneWidget);
    },
  );

  testWidgets('no notice while the double tap listens', (tester) async {
    await tester.pumpWidget(_subject(fallback: false));
    await tester.pumpAndSettle();

    expect(find.byKey(_noticeKey), findsNothing);
  });
}
