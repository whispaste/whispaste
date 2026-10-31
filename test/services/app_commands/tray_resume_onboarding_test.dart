/// The tray entry "Resume setup" (Onboarding v6, V08): it is in the tree only
/// while the first-run setup is paused, so a finished setup never shows it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;

late L10n l10n;

List<AppCommand> _tree({required bool resumeOnboardingAvailable}) =>
    buildTrayCommands(
      TrayMenuState(
        isRecording: false,
        micDeviceLabels: const [micDefaultLabel],
        selectedMic: micDefaultLabel,
        resumeOnboardingAvailable: resumeOnboardingAvailable,
      ),
      trayLabelsFor(l10n),
    );

bool _hasId(List<AppCommand> commands, String id) => commands.any(
  (c) => c.id == id || c.children.any((child) => child.id == id),
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    await loadAppFonts();
  });

  test('is offered only while the first-run setup is paused', () {
    expect(
      _hasId(
        _tree(resumeOnboardingAvailable: true),
        TrayCommandIds.resumeOnboarding,
      ),
      isTrue,
    );
    expect(
      _hasId(
        _tree(resumeOnboardingAvailable: false),
        TrayCommandIds.resumeOnboarding,
      ),
      isFalse,
      reason: 'A finished setup must not show a resume entry.',
    );
  });

  test('resolves its label through the tray label table', () {
    expect(trayLabelsFor(l10n)['trayResumeOnboarding'], 'Resume setup');
  });

  test(
    'is not part of the complete-tree id list, because it is conditional',
    () {
      expect(
        TrayCommandIds.all,
        isNot(contains(TrayCommandIds.resumeOnboarding)),
      );
    },
  );
}
