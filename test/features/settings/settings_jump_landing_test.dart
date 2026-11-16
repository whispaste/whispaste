/// A jump into Settings lands on the row it names and marks it (#1616): the
/// cloud key error lands on the configured provider's key field, also when
/// Settings is already open on another area; a row the configuration hides
/// hands over to the row that decides whether it shows; a search with no
/// match does not hide the target.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../../fixtures/test_helpers.dart';

class _AnsweringMic implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

class _Settings extends SettingsNotifier {
  _Settings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

const _viewHeight = 800.0;

/// Pumps Settings with [settings], opened on [startArea], and returns the
/// container plus the list of rows that got marked.
Future<(ProviderContainer, List<String>)> _open(
  WidgetTester tester, {
  AppSettings? settings,
  SettingsArea startArea = SettingsArea.general,
}) async {
  tester.view.physicalSize = const Size(1280, _viewHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      const SettingsPage(),
      locale: const Locale('en'),
      overrides: [
        hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
        micPermissionCheckerProvider.overrideWithValue(_AnsweringMic()),
        if (settings != null)
          settingsProvider.overrideWith(() => _Settings(settings)),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SettingsPage)),
  );
  container.read(settingsAreaProvider.notifier).select(startArea);
  await tester.pumpAndSettle();
  final marked = <String>[];
  container.listen(settingsHighlightTargetProvider, (_, next) {
    if (next != null) marked.add(next);
  });
  return (container, marked);
}

/// Sets the jump the way every caller does and lets it land.
Future<void> _jump(
  WidgetTester tester,
  ProviderContainer container,
  String target,
) async {
  container.read(settingsScrollTargetProvider.notifier).set(target);
  container.read(activePageProvider.notifier).setPage('settings');
  await tester.pumpAndSettle();
}

void _expectOnScreen(WidgetTester tester, String rowId) {
  final row = find.byKey(ValueKey('settings-row-$rowId'));
  expect(row, findsOneWidget, reason: '$rowId is not built');
  final rect = tester.getRect(row);
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$rowId above the view');
  expect(rect.top, lessThan(_viewHeight), reason: '$rowId below the view');
}

/// Lets the 1.5 s highlight timer run out before the test ends.
Future<void> _finish(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));

AppSettings _withProvider(SttProviderType provider) =>
    AppSettings.defaults.copyWith(sttProvider: provider.value);

void main() {
  for (final provider in [
    SttProviderType.openAI,
    SttProviderType.deepgram,
    SttProviderType.customEndpoint,
  ]) {
    final row = settingsRowForRecordingError('cloud_auth_error', provider)!;

    testWidgets('the key error of $provider lands on $row', (tester) async {
      final (container, marked) = await _open(
        tester,
        settings: _withProvider(provider),
      );
      await _jump(tester, container, row);
      _expectOnScreen(tester, row);
      expect(marked, [row]);
      await _finish(tester);
    });

    testWidgets('…also from Settings already open on Recording', (
      tester,
    ) async {
      final (container, marked) = await _open(
        tester,
        settings: _withProvider(provider),
        startArea: SettingsArea.recording,
      );
      await _jump(tester, container, row);
      expect(
        container.read(settingsAreaProvider),
        isNot(SettingsArea.recording),
      );
      _expectOnScreen(tester, row);
      expect(marked, [row]);
      await _finish(tester);
    });
  }

  testWidgets('a jump into the same area scrolls without a rebuild', (
    tester,
  ) async {
    final (container, marked) = await _open(
      tester,
      startArea: SettingsArea.recording,
    );
    await _jump(tester, container, 'recording-microphone');
    _expectOnScreen(tester, 'recording-microphone');
    expect(marked, ['recording-microphone']);
    await _finish(tester);
  });

  testWidgets('the engine row hidden by a cloud service lands on the service '
      'choice', (tester) async {
    final (container, marked) = await _open(
      tester,
      settings: _withProvider(SttProviderType.openAI),
    );
    await _jump(tester, container, 'stt-model');
    _expectOnScreen(tester, 'speech-provider');
    expect(marked, ['speech-provider']);
    await _finish(tester);
  });

  testWidgets('the GPU row hidden by Parakeet lands on the engine row', (
    tester,
  ) async {
    final (container, marked) = await _open(
      tester,
      settings: AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.onDevice.value,
        sttEngine: OnDeviceEngine.parakeet.value,
      ),
    );
    await _jump(tester, container, 'speech-gpu');
    _expectOnScreen(tester, 'stt-model');
    expect(marked, ['stt-model']);
    await _finish(tester);
  });

  testWidgets('a search with no match does not hide the target', (
    tester,
  ) async {
    final (container, marked) = await _open(tester);
    container.read(settingsSearchQueryProvider.notifier).set('zzzz-no-match');
    await tester.pumpAndSettle();
    await _jump(tester, container, 'recording-microphone');
    expect(container.read(settingsSearchQueryProvider), isEmpty);
    _expectOnScreen(tester, 'recording-microphone');
    expect(marked, ['recording-microphone']);
    await _finish(tester);
  });

  testWidgets('an unknown target stays put and marks nothing', (tester) async {
    final (container, marked) = await _open(
      tester,
      startArea: SettingsArea.recording,
    );
    await _jump(tester, container, 'no-such-row');
    expect(container.read(settingsAreaProvider), SettingsArea.recording);
    expect(container.read(settingsScrollTargetProvider), isNull);
    expect(marked, isEmpty);
    await _finish(tester);
  });

  testWidgets('a dictionary row opens the Wörterbuch page', (tester) async {
    final (container, _) = await _open(tester);
    await _jump(tester, container, 'dictionary-replacements');
    expect(container.read(activePageProvider), 'replacements');
    await _finish(tester);
  });
}
