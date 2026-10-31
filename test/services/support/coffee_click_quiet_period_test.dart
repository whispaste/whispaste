/// GR-021 (2026-10-25): a click on a coffee link (Ko-fi, Buy Me a Coffee)
/// starts the prompt's quiet period but never the recurring "monatliches
/// Sponsoring" follow-up. GitHub Sponsors and PayPal keep their behaviour.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support_prompt_service.dart';

const _linkClickedKey = 'support_prompt_link_clicked';
const _postLinkKey = 'support_prompt_post_link_ms';

Future<({ProviderContainer container, HistoryDatabase db})> _bootstrap({
  required Map<String, Object> prefs,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  for (var i = 0; i < 40; i++) {
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
      deployChannelProvider.overrideWithValue(DeployChannel.portable),
      supportCapabilitiesProvider.overrideWithValue(const [
        SupportAsk.kofi,
        SupportAsk.githubSponsors,
      ]),
    ],
  );
  return (container: container, db: db);
}

Future<SupportPromptState> _check(ProviderContainer container) async {
  await container.read(supportPromptProvider.notifier).checkAndMaybePrompt();
  return container.read(supportPromptProvider);
}

void main() {
  group('GR-021 coffee click', () {
    test('does not set the link-clicked flag', () async {
      final harness = await _bootstrap(prefs: const {});
      addTearDown(harness.container.dispose);
      expect((await _check(harness.container)).shouldShowPrompt, isTrue);

      await harness.container
          .read(supportPromptProvider.notifier)
          .markCoffeeLinkOpened();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_linkClickedKey), isNull);
    });

    test('keeps the quiet period: silent right after the click', () async {
      final harness = await _bootstrap(prefs: const {});
      addTearDown(harness.container.dispose);
      expect((await _check(harness.container)).shouldShowPrompt, isTrue);

      await harness.container
          .read(supportPromptProvider.notifier)
          .markCoffeeLinkOpened();

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('after the quiet period only the normal ask comes back, never the '
        'recurring follow-up', () async {
      final justOverNineMonths = DateTime.now()
          .subtract(const Duration(days: 271))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_postLinkKey: justOverNineMonths},
      );
      addTearDown(harness.container.dispose);

      final state = await _check(harness.container);
      expect(state.shouldShowPrompt, isTrue);
      expect(state.kind, SupportPromptKind.initial);
    });
  });
}
