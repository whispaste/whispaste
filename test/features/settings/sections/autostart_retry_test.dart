// The failed-autostart notice offers "Try again", which runs the sync once
// more (UIA-SET-14).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/services/autostart_service.dart';

import '../../../fixtures/test_helpers.dart';

class _FailedSync extends AutostartSyncFailureNotifier {
  @override
  Object? build() => StateError('registration refused');
}

class _CountingAutostart extends AutostartService {
  int retries = 0;

  @override
  bool build() => false;

  @override
  Future<void> retrySync() async => retries++;
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  testWidgets('"Try again" in the autostart failure notice retries the sync '
      '(UIA-SET-14)', (tester) async {
    final autostart = _CountingAutostart();
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: InterfaceGeneralSection()),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(() => _Settings()),
          autostartSyncFailureProvider.overrideWith(() => _FailedSync()),
          autostartServiceProvider.overrideWith(() => autostart),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('autostartRetryButton')));
    await tester.pumpAndSettle();

    expect(autostart.retries, 1);
  });
}
