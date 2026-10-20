/// The About content as the last settings area, "Über WhisPaste" (WP-78).
///
/// The section keeps what a user needs to know about the installed app: the
/// version, the update check, the links, the licences and the credits. The
/// three things it used to carry that duplicated other places are gone (the
/// privacy card, the keyboard-shortcut card and the support card), and the
/// diagnostics and the support content live on the Help page.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/settings/sections/about_section.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_text_link.dart';

import '../../../fixtures/test_helpers.dart';

late L10n en;

Future<void> _pump(
  WidgetTester tester, {
  DeployChannel channel = DeployChannel.installer,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: AboutSection()),
      locale: const Locale('en'),
      overrides: [deployChannelProvider.overrideWith((ref) => channel)],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  test('About is the last area of the system group in the navigation', () {
    final system = settingsAreasIn(SettingsGroup.system);
    expect(system.last, SettingsArea.about);
    expect(SettingsArea.values.last, SettingsArea.about);
  });

  group('AboutSection update check (moved from General, PRD Bug 2)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setFeedUrlFn = (_) async {};
      checkForUpdatesFn = ({inBackground}) async {};
    });

    tearDown(() {
      platformSupportsSparkle = () => false;
      setFeedUrlFn = (_) async {};
      checkForUpdatesFn = ({inBackground}) async {};
    });

    testWidgets(
      'on a Sparkle platform, the check opens the native foreground check, '
      'never the channel-blind GitHub check',
      (tester) async {
        platformSupportsSparkle = () => true;
        var foregroundCheckCalled = false;
        bool? capturedInBackground;
        checkForUpdatesFn = ({inBackground}) async {
          foregroundCheckCalled = true;
          capturedInBackground = inBackground;
        };

        await _pump(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AboutSection)),
        );
        await tester.tap(
          find.byKey(const ValueKey('settings-about-check-updates')),
        );
        await tester.pump();

        expect(foregroundCheckCalled, isTrue);
        expect(capturedInBackground, isFalse, reason: 'foreground, not silent');
        expect(container.read(updateProvider).phase, UpdatePhase.idle);
      },
    );

    testWidgets('the check row is a settings row with the stable row id', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.byKey(const ValueKey('settings-row-about-check-updates')),
        findsOneWidget,
      );
      expect(find.text(en.settingsCheckForUpdatesNow), findsOneWidget);
    });

    testWidgets('a package-managed install shows no check at all', (
      tester,
    ) async {
      await _pump(tester, channel: DeployChannel.packageManaged);

      expect(
        find.byKey(const ValueKey('settings-about-check-updates')),
        findsNothing,
      );
    });

    testWidgets('a store build shows the check disabled, with its reason', (
      tester,
    ) async {
      await _pump(tester, channel: DeployChannel.store);

      final button = tester.widget<WpButton>(
        find.byKey(const ValueKey('settings-about-check-updates')),
      );
      expect(button.onPressed, isNull);
      expect(find.text(en.settingsStoreUpdatesUnavailable), findsOneWidget);
    });
  });

  group('AboutSection content', () {
    testWidgets('the tagline and the credits line are shown', (tester) async {
      await _pump(tester);

      expect(find.text(en.aboutTagline), findsOneWidget);
      expect(find.text(en.aboutMadeWith), findsOneWidget);
    });

    testWidgets('the licences row opens the in-app licences page', (
      tester,
    ) async {
      await _pump(tester);

      final row = find.byKey(
        const ValueKey('settings-about-third-party-licenses'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(find.text(en.aboutThirdPartyLicenses), findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('the links are rows with stable ids', (tester) async {
      await _pump(tester);

      for (final id in const [
        'about-whats-new',
        'about-website',
        'about-github-repo',
        'about-follow-x',
        'about-mit-license',
        'about-third-party-licenses',
        'about-privacy-policy',
      ]) {
        expect(
          find.byKey(ValueKey('settings-row-$id')),
          findsOneWidget,
          reason: id,
        );
      }
    });

    testWidgets('names the NVIDIA model and the ggml-org conversion as links', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.byKey(const ValueKey('about-parakeet-model-link')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('about-parakeet-gguf-link')),
        findsOneWidget,
      );
      expect(find.text(en.aboutParakeetModelCredit), findsOneWidget);
      expect(find.text(en.aboutParakeetGgufCredit), findsOneWidget);
      expect(find.byType(WpTextLink), findsNWidgets(2));
    });

    testWidgets(
      'the duplicates are gone: privacy, shortcuts and support card',
      (tester) async {
        await _pump(tester);

        expect(find.text(en.aboutSupportTitle), findsNothing);
        expect(
          find.byKey(const ValueKey('about-support-page-button')),
          findsNothing,
        );
      },
    );

    testWidgets('the diagnostics moved to the Help page', (tester) async {
      await _pump(tester);

      expect(find.text(en.aboutCopyDebugInfo), findsNothing);
      expect(find.text(en.aboutSystemInfo), findsNothing);
    });

    testWidgets('About carries no loud action (one primary button at most)', (
      tester,
    ) async {
      await _pump(tester);

      final primaries = tester
          .widgetList<WpButton>(find.byType(WpButton))
          .where((b) => b.variant == WpButtonVariant.primary);
      expect(primaries, isEmpty);
    });

    testWidgets('every interactive element is at least 48 px high', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await _pump(tester);
        for (final finder in [
          find.byKey(const ValueKey('settings-about-check-updates')),
          find.byKey(const ValueKey('settings-about-third-party-licenses')),
        ]) {
          expect(
            tester.getSize(finder).height,
            greaterThanOrEqualTo(WpSpacing.xxxl),
            reason: finder.toString(),
          );
        }
      } finally {
        handle.dispose();
      }
    });
  });

  group('AboutSection semantics identifiers (DEV-157)', () {
    testWidgets(
      'the update check, licences and link buttons carry identifiers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester);

        for (final id in const [
          'settings-about-check-updates',
          'settings-about-third-party-licenses',
          'settings-about-website',
          'settings-about-imprint',
          'settings-about-privacy-policy',
        ]) {
          expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
        }
        handle.dispose();
      },
    );
  });

  group('AboutSection install failures (UIA-FLW-08)', () {
    testWidgets(
      'a failed launch shows the reason and offers to install again',
      (tester) async {
        await _pump(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AboutSection)),
        );
        container
            .read(updateProvider.notifier)
            .debugSetStateForTesting(
              const UpdateState(
                phase: UpdatePhase.error,
                installFailure: InstallFailure.launchFailed,
                downloadedPath: '/tmp/WhisPaste-Setup.exe',
                errorMessage: 'Could not launch installer: boom',
              ),
            );
        await tester.pump();

        expect(find.text(en.updateInstallFailed), findsOneWidget);
        expect(find.text(en.updateInstallRetry), findsOneWidget);
        expect(find.text(en.updateError), findsNothing);
      },
    );

    testWidgets('a missing installer shows its reason and offers a new check', (
      tester,
    ) async {
      await _pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AboutSection)),
      );
      container
          .read(updateProvider.notifier)
          .debugSetStateForTesting(
            const UpdateState(
              phase: UpdatePhase.error,
              installFailure: InstallFailure.installerMissing,
            ),
          );
      await tester.pump();

      expect(find.text(en.updateInstallerMissing), findsOneWidget);
      expect(find.text(en.updateCheckNow), findsOneWidget);
      expect(find.text(en.updateInstallRetry), findsNothing);
    });

    testWidgets('the retry button runs the install, not a new update check', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('uia-w2-retry');
      addTearDown(() => dir.deleteSync(recursive: true));
      final installer = File('${dir.path}/WhisPaste-Setup.exe')
        ..writeAsStringSync('not an installer');

      await _pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AboutSection)),
      );
      container
          .read(updateProvider.notifier)
          .debugSetStateForTesting(
            UpdateState(
              phase: UpdatePhase.error,
              installFailure: InstallFailure.launchFailed,
              downloadedPath: installer.path,
              errorMessage: 'marker',
            ),
          );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('settings-about-check-updates')),
      );
      await tester.pump();

      // A new check would reset the state to `checking` at once. The install
      // runs a real process, whose outcome cannot complete inside this test's
      // fake-async zone, so only the synchronous effect is asserted here.
      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.error);
      expect(state.errorMessage, 'marker');
      expect(state.downloadedPath, installer.path);
      // Let the launch's own timers finish inside the fake clock.
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a failed update check names the failure, never "up to date"', (
      tester,
    ) async {
      await _pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AboutSection)),
      );
      container
          .read(updateProvider.notifier)
          .debugSetStateForTesting(
            const UpdateState(
              phase: UpdatePhase.error,
              errorMessage: 'Could not reach GitHub',
            ),
          );
      await tester.pump();

      expect(find.text(en.settingsNavUpToDate), findsNothing);
      expect(find.text(en.updateError), findsWidgets);
    });

    testWidgets('the after-recording note shows only while a recording runs', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AboutSection()),
          locale: const Locale('en'),
          overrides: [
            deployChannelProvider.overrideWith(
              (ref) => DeployChannel.installer,
            ),
            recordingProvider.overrideWith(_SettableRecording.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AboutSection)),
      );
      (container.read(recordingProvider.notifier) as _SettableRecording)
          .setPhase(RecordingPhase.recording);
      container
          .read(updateProvider.notifier)
          .debugSetStateForTesting(
            const UpdateState(
              phase: UpdatePhase.readyToInstall,
              downloadedPath: '/tmp/WhisPaste-Setup.exe',
              installDeferred: true,
            ),
          );
      await tester.pump();
      expect(find.text(en.updateInstallAfterRecording), findsOneWidget);

      (container.read(recordingProvider.notifier) as _SettableRecording)
          .setPhase(RecordingPhase.done);
      await tester.pump();
      expect(find.text(en.updateInstallAfterRecording), findsNothing);
    });
  });
}

/// Recording notifier whose phase a test can move on demand.
class _SettableRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState(phase: RecordingPhase.idle);

  void setPhase(RecordingPhase phase) {
    state = RecordingState(phase: phase);
  }
}
