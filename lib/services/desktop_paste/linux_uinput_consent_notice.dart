/// One notice for users whose .deb granted /dev/uinput on install (R-02).
///
/// The package now grants nothing until the user agrees, and the upgrade
/// removes the old access. Without a word, Auto-Paste would just stop: the
/// app tells them once and leads to the setup.
library;

import 'package:shared_preferences/shared_preferences.dart';

const kLinuxUinputConsentNoticeShownKey = 'linux_uinput_consent_notice_shown';

/// Whether to show the notice now; marks it shown when it returns true.
///
/// Only for a .deb that manages the grant ([canManage]), with Auto-Paste on
/// and the onboarding done (a fresh install asks there), and only while
/// pasting is really blocked. [pasteBlocked] runs last, it probes the device.
Future<bool> takeLinuxUinputConsentNotice({
  required SharedPreferences prefs,
  required bool canManage,
  required bool autoPasteOn,
  required bool onboardingDone,
  required Future<bool> Function() pasteBlocked,
}) async {
  if (!canManage || !autoPasteOn || !onboardingDone) return false;
  if (prefs.getBool(kLinuxUinputConsentNoticeShownKey) ?? false) return false;
  if (!await pasteBlocked()) return false;
  await prefs.setBool(kLinuxUinputConsentNoticeShownKey, true);
  return true;
}
