/// The known-server choice under the own endpoint's address (#1957): picking
/// a server fills in its usual address and nothing else, and an entered
/// address shows its server.
library;

import 'package:flutter/material.dart';
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

Future<ProviderContainer> _pump(WidgetTester tester, String url) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _Settings(
          AppSettings(
            cloudProvider: CloudProviderSettings(
              customEndpointUrl: url,
              customEndpointSmartModel: 'qwen3:8b',
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
            child: CustomEndpointRows(
              scope: CustomEndpointScope.smartMode,
              loadModels: ({required base, apiKey}) async =>
                  const CustomEndpointModelList(
                    CustomEndpointModelListResult.empty,
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('picking a server fills in its address and keeps the model', (
    tester,
  ) async {
    final container = await _pump(tester, '');
    await tester.tap(
      find.byKey(const ValueKey('text-smart-mode-endpoint-server-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(
            const ValueKey(
              'text-smart-mode-endpoint-server-picker-item-Ollama',
            ),
          )
          .last,
    );
    await tester.pumpAndSettle();
    final cloud = container.read(settingsProvider).value!.cloudProvider;
    expect(cloud.customEndpointUrl, 'http://127.0.0.1:11434/v1');
    expect(cloud.customEndpointSmartModel, 'qwen3:8b');
  });

  testWidgets('an entered address without /v1 shows its server', (
    tester,
  ) async {
    await _pump(tester, 'http://127.0.0.1:1234');
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('text-smart-mode-endpoint-server-picker'),
        ),
        matching: find.text('LM Studio'),
      ),
      findsOneWidget,
    );
  });
}
