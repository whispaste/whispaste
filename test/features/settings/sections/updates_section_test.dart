/// Tests for [UpdatesSection] — release channel toggle + automatic update
/// check, and the store-channel hide rule (AC „Store-Build blendet den Toggle
/// sinnvoll aus").
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/updates_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/stable_revert_hint_service.dart';
import 'package:whispaste/services/update_channel_service.dart';
import 'package:whispaste/services/update_service.dart';

import '../../../fixtures/test_helpers.dart';

/// Fake for [StableRevertHintNotifier] — [checkAfterSwitchToStable] normally
/// fetches+parses+compares against the real network; the pure logic is
/// covered independently in `stable_revert_hint_service_test.dart`. Here we
/// only need to verify the *wiring* (Issue 06): does the toggle's
/// `onChanged` trigger the check exactly once per switch-to-stable, and does
/// the section render/hide the hint based on the resulting state.
class FakeStableRevertHintNotifier extends StableRevertHintNotifier {
  FakeStableRevertHintNotifier({
    this.shouldShow = true,
    this.version = '1.2.43',
  });

  final bool shouldShow;
  final String version;
  int checkCallCount = 0;

  @override
  Future<void> checkAfterSwitchToStable({
    String? installedVersionOverride,
  }) async {
    checkCallCount++;
    state = shouldShow
        ? StableRevertHintState(visible: true, stableVersion: version)
        : const StableRevertHintState();
  }
}

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Rejects every request instantly — keeps the manual-check test hermetic
/// (no real network call left pending after the test ends).
class _RejectInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(requestOptions: options, message: 'test: no network'),
    );
  }
}

/// Taps the [Switch] inside the [SettingRow] that shows [label].
Future<void> _tapRowSwitch(WidgetTester tester, String label) async {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(SettingRow),
  );
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pump();
}

late L10n l10n;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Tests that don't override [stableRevertHintProvider] still exercise
    // the real notifier via the toggle's onChanged wiring (Issue 06). Stub
    // the network seam so those runs resolve synchronously instead of
    // leaving a real Dio connect-timeout timer pending past test teardown.
    fetchAppcastFn = (url) async => throw Exception('test: no network');
  });

  tearDown(() {
    fetchAppcastFn = (url) async => '';
    platformSupportsSparkle = () => false;
  });

  group('UpdatesSection', () {
    testWidgets('AC-1: toggling Beta-Updates switches the channel to beta', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsBetaUpdates);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdatesSection)),
      );
      expect(container.read(updateChannelProvider).value, UpdateChannel.beta);
    });

    testWidgets('toggling Beta-Updates off returns to stable', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
      await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdatesSection)),
      );
      expect(container.read(updateChannelProvider).value, UpdateChannel.stable);
    });

    testWidgets('toggling "check for updates" writes through to settings', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(); // checkUpdates defaults true
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => notifier),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapRowSwitch(tester, l10n.settingsCheckUpdates);

      expect(notifier.state.value!.updates.checkUpdates, isFalse);
    });

    testWidgets('AC-4: section is hidden on the store deploy channel', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            deployChannelProvider.overrideWith((ref) => DeployChannel.store),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsBetaUpdates), findsNothing);
      expect(find.text(l10n.settingsCheckUpdates), findsNothing);
    });

    testWidgets(
      'AC-4b: section is hidden on the packageManaged deploy channel',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.packageManaged,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsBetaUpdates), findsNothing);
        expect(find.text(l10n.settingsCheckUpdates), findsNothing);
      },
    );

    testWidgets('renders both controls on a non-store channel', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsCheckUpdates), findsOneWidget);
      expect(find.text(l10n.settingsBetaUpdates), findsOneWidget);
      expect(find.text(l10n.settingsCheckForUpdatesNow), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets(
      'PRD Bug 5: manual "check for updates now" button routes through the '
      'shared triggerUpdateAction — before this fix, Settings had no manual '
      'check at all',
      (tester) async {
        // Force the non-Sparkle branch so the tap deterministically calls
        // `UpdateNotifier.checkForUpdate()` (observable via the phase
        // transition) rather than the native Sparkle dialog.
        platformSupportsSparkle = () => false;
        // Instant-reject network — the assertion only needs the synchronous
        // `checking` state set before the await, not a real round trip.
        UpdateNotifier.dioOverrideForTesting = Dio()
          ..interceptors.add(_RejectInterceptor());
        addTearDown(() => UpdateNotifier.dioOverrideForTesting = null);

        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(UpdatesSection)),
        );
        expect(container.read(updateProvider).phase, UpdatePhase.idle);

        final row = find.ancestor(
          of: find.text(l10n.settingsCheckForUpdatesNow),
          matching: find.byType(SettingRow),
        );
        await tester.tap(
          find.descendant(of: row, matching: find.byType(OutlinedButton)),
        );
        await tester.pump();

        expect(container.read(updateProvider).phase, UpdatePhase.checking);

        // Drain the rejected request so no timer is left pending at teardown.
        await tester.pumpAndSettle();
      },
    );
  });

  group('UpdatesSection — stable-revert hint (Issue 06, AC-7/AC-3)', () {
    testWidgets(
      'AC-7: switching Beta → Stable triggers the check once and shows the '
      'hint with the stable-download link when it resolves visible',
      (tester) async {
        final fake = FakeStableRevertHintNotifier();
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              stableRevertHintProvider.overrideWith(() => fake),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable
        await tester.pumpAndSettle();

        expect(fake.checkCallCount, 1);
        expect(find.text(l10n.settingsStableRevertHintMessage), findsOneWidget);
        expect(
          find.text(l10n.settingsStableRevertHintLink('1.2.43')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AC-3: no false hint — when the check resolves not-visible (e.g. '
      'post-promotion), nothing is rendered',
      (tester) async {
        final fake = FakeStableRevertHintNotifier(shouldShow: false);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              stableRevertHintProvider.overrideWith(() => fake),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable
        await tester.pumpAndSettle();

        expect(fake.checkCallCount, 1);
        expect(find.text(l10n.settingsStableRevertHintMessage), findsNothing);
      },
    );

    testWidgets(
      'switching to Beta dismisses an already-visible hint (no stale hint '
      'once the user opts back into Beta)',
      (tester) async {
        final fake = FakeStableRevertHintNotifier();
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              stableRevertHintProvider.overrideWith(() => fake),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable
        await tester.pumpAndSettle();
        expect(find.text(l10n.settingsStableRevertHintMessage), findsOneWidget);

        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta again
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsStableRevertHintMessage), findsNothing);
      },
    );

    testWidgets(
      'dismiss button hides the hint, and it stays hidden across rebuilds '
      '(shown once per switch — not spammy)',
      (tester) async {
        final fake = FakeStableRevertHintNotifier();
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: UpdatesSection()),
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              stableRevertHintProvider.overrideWith(() => fake),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → beta
        await _tapRowSwitch(tester, l10n.settingsBetaUpdates); // → stable
        await tester.pumpAndSettle();
        expect(find.text(l10n.settingsStableRevertHintMessage), findsOneWidget);

        await tester.tap(find.byTooltip(l10n.actionDismiss));
        await tester.pumpAndSettle();
        expect(find.text(l10n.settingsStableRevertHintMessage), findsNothing);

        // Further rebuilds (simulated navigation) must not re-trigger the
        // check or resurrect the dismissed hint.
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(fake.checkCallCount, 1);
        expect(find.text(l10n.settingsStableRevertHintMessage), findsNothing);
      },
    );

    testWidgets('hint text is localized in German', (tester) async {
      final l10nDe = await L10n.delegate.load(const Locale('de'));
      final fake = FakeStableRevertHintNotifier();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: UpdatesSection()),
          locale: const Locale('de'),
          overrides: [
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            deployChannelProvider.overrideWith((ref) => DeployChannel.portable),
            stableRevertHintProvider.overrideWith(() => fake),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final betaLabel = find.text(l10nDe.settingsBetaUpdates);
      expect(betaLabel, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.ancestor(of: betaLabel, matching: find.byType(SettingRow)),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.ancestor(of: betaLabel, matching: find.byType(SettingRow)),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10nDe.settingsStableRevertHintMessage), findsOneWidget);
      expect(
        find.text(l10nDe.settingsStableRevertHintLink('1.2.43')),
        findsOneWidget,
      );
    });
  });
}
