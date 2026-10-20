import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';

void main() {
  group('resolveStartPage', () {
    test('falls back to history without a stored page', () {
      expect(resolveStartPage(null, onboardingCompleted: true), 'history');
    });

    test('restores a restorable page once onboarding is complete', () {
      for (final id in [
        'snippets',
        'notes',
        'history',
        'replacements',
        'analytics',
        'settings',
        'help',
      ]) {
        expect(resolveStartPage(id, onboardingCompleted: true), id, reason: id);
      }
    });

    test(
      'maps the retired about id to settings, so stored starts keep working',
      () {
        expect(
          resolveStartPage('about', onboardingCompleted: true),
          'settings',
        );
        expect(
          resolveStartPage('about', onboardingCompleted: false),
          'history',
        );
      },
    );

    test('ignores unknown and removed page ids', () {
      for (final id in [
        'gone',
        '',
        'HISTORY',
        'smartMode', // opens Settings, is not a page of its own
        'feedback', // sub-page reached from Help, not a nav area
      ]) {
        expect(
          resolveStartPage(id, onboardingCompleted: true),
          'history',
          reason: id,
        );
      }
    });

    test('never restores during first-run onboarding', () {
      expect(resolveStartPage('notes', onboardingCompleted: false), 'history');
    });
  });

  group('canonicalPageId', () {
    test('maps about to settings and support to help, others unchanged', () {
      expect(canonicalPageId('about'), 'settings');
      expect(canonicalPageId('help'), 'help');
      expect(canonicalPageId('settings'), 'settings');
      expect(canonicalPageId('support'), 'help');
    });

    test(
      'a retired support id is restored, remembered and started as help',
      () {
        expect(resolveStartPage('support', onboardingCompleted: true), 'help');
        expect(persistablePage('support', surfaceActive: false), 'help');
      },
    );
  });

  group('ActivePageNotifier retired ids carry their target', () {
    test('a jump to the retired about id lands on Settings at About', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activePageProvider.notifier).setPage('about');

      expect(container.read(activePageProvider), 'settings');
      expect(container.read(settingsScrollTargetProvider), 'about');
    });

    test('restoring the retired about id also lands on Settings at About', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activePageProvider.notifier).restore('about');

      expect(container.read(activePageProvider), 'settings');
      expect(container.read(settingsScrollTargetProvider), 'about');
    });

    test('a jump to the retired support id lands on the Support tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activePageProvider.notifier).setPage('support');

      expect(container.read(activePageProvider), 'help');
      expect(
        container.read(helpTargetProvider),
        const HelpTarget(tab: HelpTab.support),
      );
    });

    test('restoring the retired support id lands on the Support tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activePageProvider.notifier).restore('support');

      expect(container.read(activePageProvider), 'help');
      expect(
        container.read(helpTargetProvider),
        const HelpTarget(tab: HelpTab.support),
      );
    });
  });

  group('persistablePage', () {
    test('remembers help, and remembers a stored about as settings', () {
      expect(persistablePage('help', surfaceActive: false), 'help');
      expect(persistablePage('about', surfaceActive: false), 'settings');
    });

    test('returns the page id for a restorable page outside overlays', () {
      expect(persistablePage('notes', surfaceActive: false), 'notes');
    });

    test('returns null while an onboarding surface is on top', () {
      expect(persistablePage('notes', surfaceActive: true), isNull);
    });

    test('returns null for ids that are not restorable', () {
      expect(persistablePage('feedback', surfaceActive: false), isNull);
      expect(persistablePage('smartMode', surfaceActive: false), isNull);
    });
  });

  group('ActivePageNotifier', () {
    test('starts on history by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activePageProvider), 'history');
    });

    test('restore sets the start page without leaving history first', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activePageProvider.notifier).restore('notes');
      expect(container.read(activePageProvider), 'notes');
    });
  });

  group('last page persistence (app_settings row)', () {
    test('writes and reads back the last page', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(await db.readLastPage(), isNull);
      await db.writeLastPage('analytics');
      expect(await db.readLastPage(), 'analytics');
      await db.writeLastPage('notes');
      expect(await db.readLastPage(), 'notes');
    });

    test('survives a regular settings write of other keys', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.writeLastPage('replacements');
      await db.writeAppSettings({'locale': 'de'});
      expect(await db.readLastPage(), 'replacements');
    });
  });
}
