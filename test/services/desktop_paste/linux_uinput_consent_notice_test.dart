/// R-02 (2b): users upgrading a .deb that granted /dev/uinput on install
/// lose Auto-Paste until they agree. They are told once, not at every start.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/desktop_paste/linux_uinput_consent_notice.dart';

void main() {
  Future<bool> due({
    bool canManage = true,
    bool autoPasteOn = true,
    bool onboardingDone = true,
    bool pasteBlocked = true,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    return takeLinuxUinputConsentNotice(
      prefs: await SharedPreferences.getInstance(),
      canManage: canManage,
      autoPasteOn: autoPasteOn,
      onboardingDone: onboardingDone,
      pasteBlocked: () async => pasteBlocked,
    );
  }

  test(
    'an upgraded .deb with Auto-Paste on and no access is told once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Future<bool> take() => takeLinuxUinputConsentNotice(
        prefs: prefs,
        canManage: true,
        autoPasteOn: true,
        onboardingDone: true,
        pasteBlocked: () async => true,
      );

      expect(await take(), isTrue);
      expect(await take(), isFalse);
    },
  );

  test('not for other formats, Auto-Paste off or a fresh install', () async {
    expect(await due(canManage: false), isFalse);
    expect(await due(autoPasteOn: false), isFalse);
    expect(
      await due(onboardingDone: false),
      isFalse,
      reason: 'the onboarding asks for the permission itself',
    );
  });

  test('not when Auto-Paste still works or the notice was shown', () async {
    expect(await due(pasteBlocked: false), isFalse);
    expect(
      await due(stored: {kLinuxUinputConsentNoticeShownKey: true}),
      isFalse,
    );
  });

  test('a working paste does not use up the notice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await takeLinuxUinputConsentNotice(
      prefs: prefs,
      canManage: true,
      autoPasteOn: true,
      onboardingDone: true,
      pasteBlocked: () async => false,
    );

    expect(prefs.getBool(kLinuxUinputConsentNoticeShownKey), isNull);
  });
}
