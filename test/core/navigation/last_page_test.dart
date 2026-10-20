import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/last_page.dart';
import 'package:whispaste/core/navigation/page_state.dart';

/// Settings with onboarding already completed, so restore and remember apply.
class _OnboardedSettings extends SettingsNotifier {
  _OnboardedSettings(this.completed);
  final bool completed;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    onboarding: AppSettings.defaults.onboarding.copyWith(
      onboardingCompleted: completed,
    ),
  );
}

ProviderContainer _container({
  required HistoryDatabase db,
  bool onboardingCompleted = true,
}) {
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      settingsProvider.overrideWith(
        () => _OnboardedSettings(onboardingCompleted),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('restorable pages are exactly the navigation pages', () {
    final l10n = lookupL10n(const Locale('en'));
    final navIds = {
      for (final item in wpNavItems(l10n))
        if (item.id != 'smartMode') item.id,
      wpHelpNavItem(l10n).id,
      'settings',
    };
    expect(kRestorablePageIds, navIds);
  });

  test('restores the stored page on start', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.writeLastPage('notes');
    final container = _container(db: db);

    await restoreLastPage(container);

    expect(container.read(activePageProvider), 'notes');
  });

  test(
    'a page remembered under the retired about id restores as settings',
    () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.writeLastPage('about');
      final container = _container(db: db);

      await restoreLastPage(container);

      expect(container.read(activePageProvider), 'settings');
      expect(container.read(settingsScrollTargetProvider), 'about');
    },
  );

  test('falls back to history when the stored page was removed', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.writeLastPage('feedback');
    final container = _container(db: db);

    await restoreLastPage(container);

    expect(container.read(activePageProvider), 'history');
  });

  test('does not restore before onboarding is complete', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.writeLastPage('notes');
    final container = _container(db: db, onboardingCompleted: false);

    await restoreLastPage(container);

    expect(container.read(activePageProvider), 'history');
  });

  test('a navigation is remembered for the next start', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final container = _container(db: db);
    await restoreLastPage(container);

    container.read(activePageProvider.notifier).setPage('replacements');
    await Future<void>.delayed(Duration.zero);

    expect(await db.readLastPage(), 'replacements');
  });

  test('nothing is remembered while onboarding is running', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.writeLastPage('notes');
    final container = _container(db: db, onboardingCompleted: false);
    await restoreLastPage(container);

    container.read(activePageProvider.notifier).setPage('analytics');
    await Future<void>.delayed(Duration.zero);

    expect(await db.readLastPage(), 'notes');
  });
}
