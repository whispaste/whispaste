/// Pure-Dart tests for [GitHubInviteNotifier] trigger logic.
///
/// Covers: store-only gating, the recording milestone, the cap of two
/// displays across sessions, the 30-day spacing (also after "Später"),
/// "Nicht mehr fragen" as a permanent stop, and opening GitHub as an end.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/github_invite_service.dart';

Future<({ProviderContainer container, HistoryDatabase db})> _bootstrap({
  Map<String, Object> prefs = const {},
  int activeEntries = 0,
  DeployChannel channel = DeployChannel.store,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  for (var i = 0; i < activeEntries; i++) {
    await db.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: 'entry-$i',
        timestamp: DateTime(2025, 1, 1).add(Duration(minutes: i)),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      deployChannelProvider.overrideWithValue(channel),
    ],
  );
  return (container: container, db: db);
}

/// Runs one evaluation and returns the resulting [shouldShowInvite] flag.
Future<bool> _due(ProviderContainer container, {required DateTime now}) async {
  final notifier = container.read(githubInviteProvider.notifier);
  notifier.deferInvite();
  await notifier.checkAndMaybeInvite(now: now);
  return container.read(githubInviteProvider).shouldShowInvite;
}

const _lastShownKey = 'github_invite_last_shown';

void main() {
  final t0 = DateTime(2026, 10, 1, 12);

  group('channel gating', () {
    test('portable and installer builds never get the invitation', () async {
      for (final channel in [DeployChannel.portable, DeployChannel.installer]) {
        final h = await _bootstrap(activeEntries: 60, channel: channel);
        addTearDown(h.container.dispose);
        expect(await _due(h.container, now: t0), isFalse, reason: '$channel');
      }
    });

    test('a store build with enough recordings is due', () async {
      final h = await _bootstrap(activeEntries: 40);
      addTearDown(h.container.dispose);
      expect(await _due(h.container, now: t0), isTrue);
    });
  });

  group('milestone', () {
    test('not due below 40 active recordings', () async {
      final h = await _bootstrap(activeEntries: 39);
      addTearDown(h.container.dispose);
      expect(await _due(h.container, now: t0), isFalse);
    });
  });

  group('cap and spacing', () {
    test('at most two displays in total across sessions', () async {
      final h = await _bootstrap(
        activeEntries: 40,
        prefs: const {'github_invite_impression_count': 2},
      );
      addTearDown(h.container.dispose);
      expect(await _due(h.container, now: t0), isFalse);
    });

    test('a second display needs 30 days after the first', () async {
      final h = await _bootstrap(activeEntries: 40);
      addTearDown(h.container.dispose);
      final notifier = h.container.read(githubInviteProvider.notifier);

      await notifier.recordImpression(now: t0);
      notifier.deferInvite();

      expect(
        await _due(h.container, now: t0.add(const Duration(days: 29))),
        isFalse,
      );
      expect(
        await _due(h.container, now: t0.add(const Duration(days: 30))),
        isTrue,
      );
    });

    test('"Später" keeps the 30-day spacing and counts as a display', () async {
      final h = await _bootstrap(activeEntries: 40);
      addTearDown(h.container.dispose);
      final notifier = h.container.read(githubInviteProvider.notifier);

      expect(await _due(h.container, now: t0), isTrue);
      await notifier.recordImpression(now: t0);
      await notifier.dismiss(permanent: false);
      expect(h.container.read(githubInviteProvider).shouldShowInvite, isFalse);

      expect(
        await _due(h.container, now: t0.add(const Duration(days: 10))),
        isFalse,
      );
      // Second and last display after 30 days.
      final later = t0.add(const Duration(days: 31));
      expect(await _due(h.container, now: later), isTrue);
      await notifier.recordImpression(now: later);
      await notifier.dismiss(permanent: false);

      // The cap of two is reached: no third display, even years later.
      expect(
        await _due(h.container, now: later.add(const Duration(days: 400))),
        isFalse,
      );
    });

    test('the spacing key is written on display, not on evaluation', () async {
      final h = await _bootstrap(activeEntries: 40);
      addTearDown(h.container.dispose);

      expect(await _due(h.container, now: t0), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_lastShownKey), isNull);
    });
  });

  group('endings', () {
    test('"Nicht mehr fragen" is permanent', () async {
      final h = await _bootstrap(activeEntries: 40);
      addTearDown(h.container.dispose);
      final notifier = h.container.read(githubInviteProvider.notifier);

      expect(await _due(h.container, now: t0), isTrue);
      await notifier.dismiss(permanent: true);

      expect(
        await _due(h.container, now: t0.add(const Duration(days: 400))),
        isFalse,
      );
    });

    test(
      'opening GitHub from the invitation ends further invitations',
      () async {
        final h = await _bootstrap(activeEntries: 40);
        addTearDown(h.container.dispose);
        final notifier = h.container.read(githubInviteProvider.notifier);

        expect(await _due(h.container, now: t0), isTrue);
        await notifier.recordImpression(now: t0);
        await notifier.markStarOpened();

        expect(
          await _due(h.container, now: t0.add(const Duration(days: 400))),
          isFalse,
        );
      },
    );
  });
}
