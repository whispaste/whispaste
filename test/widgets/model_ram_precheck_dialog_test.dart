import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart'
    show kSttModelChoicePrefix;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';
import 'package:whispaste/core/app_navigator.dart' show appNavigatorKey;
import 'package:whispaste/widgets/model_ram_precheck_dialog.dart';

import '../fixtures/test_helpers.dart';

/// Runs [ask] on a tap and records its answer on screen.
class _AskHarness extends StatefulWidget {
  const _AskHarness({required this.ask});

  final Future<bool> Function(BuildContext context) ask;

  @override
  State<_AskHarness> createState() => _AskHarnessState();
}

class _AskHarnessState extends State<_AskHarness> {
  String _result = 'pending';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: () async {
            final proceed = await widget.ask(context);
            if (!mounted) return;
            setState(() => _result = '$proceed');
          },
          child: const Text('Select model'),
        ),
        Text('result=$_result'),
      ],
    );
  }
}

Future<L10n> _en() => L10n.delegate.load(const Locale('en'));

/// Settings for an on-device user; the path under test changes the rest.
AppSettings _onDevice() =>
    AppSettings.defaults.copyWith(sttProvider: SttProviderType.onDevice.value);

/// A model that needs 2600 MB against 1000 MB free is clearly short.
const _shortSnapshot = MemorySnapshot(totalMB: 8192, availableMB: 1000);
const _roomySnapshot = MemorySnapshot(totalMB: 16384, availableMB: 9000);

/// Parakeet needs about 639 MB; 100 MB free is clearly short.
const _parakeetShortSnapshot = MemorySnapshot(totalMB: 8192, availableMB: 100);

const _largeModel = 'whisper-large-v3-turbo';

Future<void> _pumpAsk(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) ask,
) async {
  await tester.pumpWidget(
    makeTestable(_AskHarness(ask: ask), locale: const Locale('en')),
  );
}

/// Taps the trigger and expects the question; Abbrechen must not load.
Future<void> _expectAskThenCancel(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) ask,
) async {
  await _pumpAsk(tester, ask);
  await tester.tap(find.text('Select model'));
  await tester.pumpAndSettle();

  final l10n = await _en();
  expect(find.text(l10n.modelRamPrecheckContinue), findsOneWidget);
  await tester.tap(find.text(l10n.actionCancel));
  await tester.pumpAndSettle();
  expect(find.text('result=false'), findsOneWidget);
}

/// Taps the trigger and expects the question; Trotzdem laden must load.
Future<void> _expectAskThenLoad(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) ask,
) async {
  await _pumpAsk(tester, ask);
  await tester.tap(find.text('Select model'));
  await tester.pumpAndSettle();

  final l10n = await _en();
  await tester.tap(find.text(l10n.modelRamPrecheckContinue));
  await tester.pumpAndSettle();
  expect(find.text('result=true'), findsOneWidget);
}

/// Taps the trigger and expects no question: the load goes ahead.
Future<void> _expectNoAsk(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) ask,
) async {
  await _pumpAsk(tester, ask);
  await tester.tap(find.text('Select model'));
  await tester.pumpAndSettle();

  final l10n = await _en();
  expect(find.text(l10n.modelRamPrecheckContinue), findsNothing);
  expect(find.text('result=true'), findsOneWidget);
}

void main() {
  group(
    'model choice paths: a clearly short load asks, Abbrechen keeps it',
    () {
      testWidgets('dock and tray choice (applySttChoice)', (tester) async {
        final settings = applySttChoice(
          _onDevice(),
          '$kSttModelChoicePrefix$_largeModel',
        );
        await _expectAskThenCancel(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _shortSnapshot,
          ),
        );
      });

      testWidgets('engine dropdown switches to Parakeet', (tester) async {
        final settings = applyEngineChoice(
          _onDevice(),
          OnDeviceEngine.parakeet.value,
          downloaded: const {},
          models: const [],
        );
        await _expectAskThenCancel(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _parakeetShortSnapshot,
          ),
        );
      });

      testWidgets('benchmark switch to the recommended model', (tester) async {
        final settings = _onDevice().copyWith(sttModel: _largeModel);
        await _expectAskThenCancel(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _shortSnapshot,
          ),
        );
      });

      testWidgets('onboarding download of a Whisper model', (tester) async {
        final settings = _onDevice().copyWith(
          sttEngine: OnDeviceEngine.whisper.value,
          sttModel: _largeModel,
        );
        await _expectAskThenCancel(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _shortSnapshot,
          ),
        );
      });

      testWidgets('tier download in Settings', (tester) async {
        final settings = _onDevice().copyWith(
          sttEngine: OnDeviceEngine.whisper.value,
          sttModel: _largeModel,
        );
        await _expectAskThenCancel(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _shortSnapshot,
          ),
        );
      });

      testWidgets('model manager choice (Trotzdem laden loads)', (
        tester,
      ) async {
        final settings = _onDevice().copyWith(sttModel: _largeModel);
        await _expectAskThenLoad(
          tester,
          (context) => confirmSttSettingsRam(
            context: context,
            settings: settings,
            readSnapshot: () async => _shortSnapshot,
          ),
        );
      });

      testWidgets(
        'dock and tray reach the question through the app navigator',
        (tester) async {
          final l10n = await _en();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: appNavigatorKey,
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: _AskHarness(
                  ask: (_) => confirmSttSettingsRamFromApp(
                    settings: applySttChoice(
                      _onDevice(),
                      '$kSttModelChoicePrefix$_largeModel',
                    ),
                    readSnapshot: () async => _shortSnapshot,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Select model'));
          await tester.pumpAndSettle();

          expect(find.text(l10n.modelRamPrecheckContinue), findsOneWidget);
          await tester.tap(find.text(l10n.actionCancel));
          await tester.pumpAndSettle();
          expect(find.text('result=false'), findsOneWidget);
        },
      );
    },
  );

  group('no question', () {
    testWidgets('a model that is not on disk yet does not load', (
      tester,
    ) async {
      final settings = applyEngineChoice(
        _onDevice(),
        OnDeviceEngine.parakeet.value,
        downloaded: const {},
        models: const [],
      );
      await _expectNoAsk(
        tester,
        (context) => confirmSttSettingsRam(
          context: context,
          settings: settings,
          loads: false,
          readSnapshot: () async => _parakeetShortSnapshot,
        ),
      );
    });

    testWidgets('a cloud provider never loads a local model', (tester) async {
      final cloud = AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.values.firstWhere((p) => !p.isLocal).value,
      );
      await _expectNoAsk(
        tester,
        (context) => confirmSttSettingsRam(
          context: context,
          settings: cloud,
          readSnapshot: () async => _shortSnapshot,
        ),
      );
    });

    testWidgets('unknown free memory never asks', (tester) async {
      await _expectNoAsk(
        tester,
        (context) => confirmSttSettingsRam(
          context: context,
          settings: _onDevice().copyWith(sttModel: _largeModel),
          readSnapshot: () async => null,
        ),
      );
    });

    testWidgets('a model that fits loads without a question', (tester) async {
      await _expectNoAsk(
        tester,
        (context) => confirmSttSettingsRam(
          context: context,
          settings: _onDevice().copyWith(sttModel: 'whisper-medium'),
          readSnapshot: () async => _roomySnapshot,
        ),
      );
    });
  });

  group('start notice', () {
    testWidgets('shows once, asks nothing and does not block the load', (
      tester,
    ) async {
      var shown = false;
      await tester.pumpWidget(
        makeTestable(
          _AskHarness(
            ask: (context) async {
              shown = await showWpModelRamStartupNotice(
                context: context,
                engine: OnDeviceEngine.whisper,
                modelId: _largeModel,
                readSnapshot: () async => _shortSnapshot,
              );
              // The model is not held back: the start goes on either way.
              return true;
            },
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.text('Select model'));
      // Step through frames instead of settling: the toast runs animations
      // and timers that a settle would race with.
      await tester.pump();
      await tester.pump();

      final l10n = await _en();
      expect(shown, isTrue);
      expect(find.textContaining('2600 MB'), findsOneWidget);
      expect(find.text(l10n.modelRamPrecheckContinue), findsNothing);
      expect(find.text('result=true'), findsOneWidget);
      // Let the toast finish, then drop the tree so no animation outlives it.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays silent when the memory fits', (tester) async {
      var shown = true;
      await tester.pumpWidget(
        makeTestable(
          _AskHarness(
            ask: (context) async {
              shown = await showWpModelRamStartupNotice(
                context: context,
                engine: OnDeviceEngine.whisper,
                modelId: 'whisper-medium',
                readSnapshot: () async => _roomySnapshot,
              );
              return true;
            },
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();

      expect(shown, isFalse);
      expect(find.textContaining('MB'), findsNothing);
    });
  });
}
