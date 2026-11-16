/// Widget tests for the Settings → Privacy row of a recording waiting for a
/// retry. Each row states until when its audio is kept. The date comes from
/// the same stored `expiresAt` that the purge deletes by. Checked at 800 px,
/// with text scaling 1.3, and in a right-to-left language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show DateFormat;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/services/pending_audio/pending_audio_providers.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';

import '../../../fixtures/test_helpers.dart';

const _entryId = '1781775015020-0020';
final _expiresAt = DateTime(2026, 10, 27, 14, 30);
final _capturedAt = DateTime(2026, 10, 26, 9, 15);

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 1000),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SingleChildScrollView(child: PrivacySection()),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        pendingRetryListProvider.overrideWith(
          (ref) async => [
            PendingRetry(
              entryId: _entryId,
              capturedAt: _capturedAt,
              errorCode: 'stt_server_failed',
              expiresAt: _expiresAt,
            ),
          ],
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Finder _keptUntilRow() =>
    find.byKey(const ValueKey('privacy-pending-audio-kept-until-$_entryId'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('states the local date and time until which the audio is kept', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await _pump(tester);

    final formatted = DateFormat.yMd('en').add_Hm().format(_expiresAt);
    expect(_keptUntilRow(), findsOneWidget);
    expect(
      tester.widget<Text>(_keptUntilRow()).data,
      contains(l10n.pendingAudioKeptUntil(formatted)),
    );
    expect(tester.takeException(), isNull);
  });
}
