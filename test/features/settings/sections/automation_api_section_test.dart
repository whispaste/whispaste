/// Tests for the custom-port input added to [AutomationApiSection] (port
/// robustness ticket, `.scratch/automation-api-port-robustness/`).
///
/// Covers:
///   - [isValidAutomationApiCustomPortInput], the pure validation function
///     backing the field (empty → "automatic"; otherwise 1024–65535).
///   - The field persists a valid value to
///     `AutomationApiSettings.customPort` and shows an inline error — no
///     persistence, no crash — for an invalid one.
///   - The status row shows the fallback-port hint once the controller
///     state reports a bound port that differs from the requested one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/automation_api_section.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
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

/// Reports a fixed [AutomationApiState] instead of ever starting a real
/// server — this section reads [state] purely for display.
class _FixedAutomationApiController extends AutomationApiController {
  _FixedAutomationApiController(this._fixedState);

  final AutomationApiState _fixedState;

  @override
  AutomationApiState build() => _fixedState;
}

Widget _pump(
  WidgetTester tester, {
  AppSettings? settings,
  AutomationApiState? apiState,
}) {
  return makeTestable(
    const SingleChildScrollView(child: AutomationApiSection()),
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
      if (apiState != null)
        automationApiControllerProvider.overrideWith(
          () => _FixedAutomationApiController(apiState),
        ),
    ],
  );
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('isValidAutomationApiCustomPortInput', () {
    test('empty input is valid — means "automatic"', () {
      expect(isValidAutomationApiCustomPortInput(''), isTrue);
    });

    test('a plain integer inside 1024–65535 is valid', () {
      expect(isValidAutomationApiCustomPortInput('8766'), isTrue);
      expect(isValidAutomationApiCustomPortInput('1024'), isTrue);
      expect(isValidAutomationApiCustomPortInput('65535'), isTrue);
    });

    test('below 1024 is invalid', () {
      expect(isValidAutomationApiCustomPortInput('1023'), isFalse);
      expect(isValidAutomationApiCustomPortInput('80'), isFalse);
    });

    test('above 65535 is invalid', () {
      expect(isValidAutomationApiCustomPortInput('65536'), isFalse);
    });

    test('non-numeric input is invalid', () {
      expect(isValidAutomationApiCustomPortInput('abc'), isFalse);
      expect(isValidAutomationApiCustomPortInput('87.5'), isFalse);
    });
  });

  group('AutomationApiSection custom port field', () {
    testWidgets(
      'entering a valid port persists it to AutomationApiSettings.customPort',
      (tester) async {
        await tester.pumpWidget(_pump(tester));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '8766');
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AutomationApiSection)),
        );
        final persisted = await container.read(settingsProvider.future);
        expect(persisted.automationApi.customPort, 8766);
      },
    );

    testWidgets(
      'entering an out-of-range port shows an inline error and does not '
      'persist it',
      (tester) async {
        await tester.pumpWidget(_pump(tester));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '80');
        await tester.pump();

        expect(
          find.text(l10n.settingsAutomationApiCustomPortInvalid),
          findsOneWidget,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AutomationApiSection)),
        );
        final persisted = await container.read(settingsProvider.future);
        expect(persisted.automationApi.customPort, isNull);
      },
    );

    testWidgets('clearing the field back to empty resets it to automatic', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pump(
          tester,
          settings: AppSettings.defaults.copyWithSections(
            automationApi: const AutomationApiSettings(customPort: 8766),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AutomationApiSection)),
      );
      final persisted = await container.read(settingsProvider.future);
      expect(persisted.automationApi.customPort, isNull);
    });
  });

  group('AutomationApiSection status row', () {
    testWidgets(
      'running on the requested port shows the plain "running" status',
      (tester) async {
        await tester.pumpWidget(
          _pump(
            tester,
            settings: AppSettings.defaults.copyWithSections(
              automationApi: const AutomationApiSettings(enabled: true),
            ),
            apiState: const AutomationApiState(
              runState: AutomationApiRunState.running,
              port: 8765,
              requestedPort: 8765,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.settingsAutomationApiStatusRunning(8765)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'running on a fallback port shows which port was actually bound and '
      'which one was taken',
      (tester) async {
        await tester.pumpWidget(
          _pump(
            tester,
            settings: AppSettings.defaults.copyWithSections(
              automationApi: const AutomationApiSettings(enabled: true),
            ),
            apiState: const AutomationApiState(
              runState: AutomationApiRunState.running,
              port: 8766,
              requestedPort: 8765,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            l10n.settingsAutomationApiStatusRunningFallback(8766, 8765),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'every fallback port exhausted shows the specific port-range error',
      (tester) async {
        await tester.pumpWidget(
          _pump(
            tester,
            settings: AppSettings.defaults.copyWithSections(
              automationApi: const AutomationApiSettings(enabled: true),
            ),
            apiState: const AutomationApiState(
              runState: AutomationApiRunState.error,
              requestedPort: 8765,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.settingsAutomationApiStatusError(8765, 8784)),
          findsOneWidget,
        );
      },
    );
  });
}
