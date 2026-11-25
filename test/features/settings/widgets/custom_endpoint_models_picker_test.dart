/// "Modelle laden" hands the server's names to the model field (#1790): the
/// request runs only on the button, a picked name lands in the settings, and a
/// failure leaves the typed name alone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/widgets/custom_endpoint_rows.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_models.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._s);
  final AppSettings _s;

  @override
  Future<AppSettings> build() async => _s;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _s));
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required CustomEndpointModelsFn loadModels,
  CustomEndpointScope scope = CustomEndpointScope.speech,
  String url = 'http://localhost:1234/v1',
  String model = '',
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _Settings(
          AppSettings(
            cloudProvider: CloudProviderSettings(
              customEndpointUrl: url,
              customEndpointSttModel: model,
              customEndpointSmartModel: model,
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomEndpointRows(scope: scope, loadModels: loadModels),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('nothing is requested until the button is pressed', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      loadModels: ({required base, apiKey}) async {
        calls++;
        return const CustomEndpointModelList(
          CustomEndpointModelListResult.empty,
        );
      },
    );
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.tap(
      find.byKey(const ValueKey('speech-custom-endpoint-models-load-button')),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('a picked model lands in the settings of its scope', (
    tester,
  ) async {
    Uri? asked;
    final container = await _pump(
      tester,
      scope: CustomEndpointScope.smartMode,
      model: 'typed',
      loadModels: ({required base, apiKey}) async {
        asked = base;
        return const CustomEndpointModelList(
          CustomEndpointModelListResult.loaded,
          models: ['llama', 'qwen'],
        );
      },
    );
    await tester.tap(
      find.byKey(const ValueKey('text-smart-mode-endpoint-models-load-button')),
    );
    await tester.pumpAndSettle();
    expect(asked, Uri.parse('http://localhost:1234/v1'));

    await tester.tap(
      find.byKey(const ValueKey('text-smart-mode-endpoint-models-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(
            const ValueKey('text-smart-mode-endpoint-models-picker-item-qwen'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    final cloud = container.read(settingsProvider).value!.cloudProvider;
    expect(cloud.customEndpointSmartModel, 'qwen');
    expect(cloud.customEndpointSttModel, 'typed');
  });

  testWidgets('a failure is reported and the typed name stays', (tester) async {
    final container = await _pump(
      tester,
      model: 'my-model',
      loadModels: ({required base, apiKey}) async =>
          const CustomEndpointModelList(
            CustomEndpointModelListResult.unreachable,
          ),
    );
    await tester.tap(
      find.byKey(const ValueKey('speech-custom-endpoint-models-load-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('speech-custom-endpoint-models-result')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('speech-custom-endpoint-models-picker')),
      findsNothing,
    );
    expect(
      container
          .read(settingsProvider)
          .value!
          .cloudProvider
          .customEndpointSttModel,
      'my-model',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('speech-custom-endpoint-model-field')),
        matching: find.byType(TextField),
      ),
      'manual-after-error',
    );
    await tester.pump();
    expect(
      container
          .read(settingsProvider)
          .value!
          .cloudProvider
          .customEndpointSttModel,
      'manual-after-error',
    );
  });

  for (final changeKey in [false, true]) {
    testWidgets(
      'changing ${changeKey ? 'key' : 'URL'} discards pending models',
      (tester) async {
        final pending = Completer<CustomEndpointModelList>();
        final container = await _pump(
          tester,
          loadModels: ({required base, apiKey}) => pending.future,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('speech-custom-endpoint-models-load-button'),
          ),
        );
        await tester.pump();
        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                cloudProvider: s.cloudProvider.copyWith(
                  customEndpointUrl: changeKey
                      ? null
                      : 'http://localhost:5678/v1',
                  customEndpointApiKey: changeKey ? 'new-key' : null,
                ),
              ),
            );
        await tester.pump();
        pending.complete(
          const CustomEndpointModelList(
            CustomEndpointModelListResult.loaded,
            models: ['stale'],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('speech-custom-endpoint-models-picker')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('speech-custom-endpoint-models-result')),
          findsNothing,
        );
      },
    );
  }

  testWidgets('model loading and selection work with the keyboard', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await _pump(
      tester,
      loadModels: ({required base, apiKey}) async =>
          const CustomEndpointModelList(
            CustomEndpointModelListResult.loaded,
            models: ['llama', 'qwen'],
          ),
    );
    // URL, known-server choice (#1957), key, key visibility, model, then
    // Load models.
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Models on the server')), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      container
          .read(settingsProvider)
          .value!
          .cloudProvider
          .customEndpointSttModel,
      isIn(['llama', 'qwen']),
    );
    semantics.dispose();
  });

  testWidgets('without a valid address the button stays off', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      url: '',
      loadModels: ({required base, apiKey}) async {
        calls++;
        return const CustomEndpointModelList(
          CustomEndpointModelListResult.empty,
        );
      },
    );
    await tester.tap(
      find.byKey(const ValueKey('speech-custom-endpoint-models-load-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
