/// Tests for the sponsor-chip restore toggle on the Help page (Hilfe).
///
/// The toggle hides or restores the chip for every user (growth review R-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../../fixtures/support_fakes.dart';
import '../../../fixtures/test_helpers.dart';

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

const _toggle = ValueKey('settings-sponsor-chip-restore');

Future<FakeSupportStatusNotifier> _pump(
  WidgetTester tester,
  SupportStatus status,
) async {
  final support = FakeSupportStatusNotifier(status);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: SponsorChipRow()),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(_FakeSettings.new),
        supportStatusProvider.overrideWith(() => support),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return support;
}

void main() {
  testWidgets('chip shown without a purchase: toggle is on and can hide it', (
    tester,
  ) async {
    final support = await _pump(tester, const SupportStatus());
    final toggle = tester.widget<Switch>(find.byKey(_toggle));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNotNull);
    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(support.calls, ['hideChip']);
  });

  testWidgets('verified supporter may hide the chip', (tester) async {
    final support = await _pump(
      tester,
      const SupportStatus(verifiedSupporter: true),
    );

    final toggle = tester.widget<Switch>(find.byKey(_toggle));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNotNull);

    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(support.calls, ['hideChip']);
  });

  testWidgets('self-declared supporter may hide the chip', (tester) async {
    final support = await _pump(
      tester,
      const SupportStatus(selfDeclaredSupporter: true),
    );

    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(support.calls, ['hideChip']);
  });

  testWidgets('hidden chip can always be restored', (tester) async {
    final support = await _pump(tester, const SupportStatus(chipHidden: true));

    final toggle = tester.widget<Switch>(find.byKey(_toggle));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNotNull);

    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(support.calls, ['restoreChip']);
  });
}
