/// The About content as the last settings area, "Über WhisPaste" (ticket).
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
import 'package:whispaste/features/settings/sections/about_section.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../../fixtures/test_helpers.dart';

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
      'on a Sparkle platform, the check runs quietly so the result shows in '
      'the app (#1881), never the channel-blind GitHub check',
      (tester) async {
        platformSupportsSparkle = () => true;
        var sparkleCheckCalled = false;
        bool? capturedInBackground;
        checkForUpdatesFn = ({inBackground}) async {
          sparkleCheckCalled = true;
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

        expect(sparkleCheckCalled, isTrue);
        expect(
          capturedInBackground,
          isTrue,
          reason: 'quiet: no native "up to date" window (#1881)',
        );
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
    });
  });

  group('AboutSection content', () {
    testWidgets('the licences row opens the in-app licences page', (
      tester,
    ) async {
      await _pump(tester);

      final row = find.byKey(
        const ValueKey('settings-about-third-party-licenses'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();

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
  });
}
