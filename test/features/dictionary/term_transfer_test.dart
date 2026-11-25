import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/dictionary/term_import_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  bool fail = false;
  int writes = 0;
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(customVocabulary: 'OpenAI');

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    writes++;
    final updated = updater(state.requireValue);
    if (fail) {
      ref.read(settingsSaveFailuresProvider.notifier).record();
    } else {
      state = AsyncData(updated);
    }
  }
}

void main() {
  testWidgets(
    'drop preview waits for confirmation and writes only selected new terms',
    (tester) async {
      final settings = _Settings();
      await tester.pumpWidget(
        makeTestable(
          const TermImportPage(),
          overrides: [settingsProvider.overrideWith(() => settings)],
        ),
      );
      await tester.pumpAndSettle();
      final drop = tester.widget<DropTarget>(find.byType(DropTarget));
      drop.onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile.fromData(
              utf8.encode('term\nOpenAI\nKubernetes\nFlutter\n...'),
              name: 'terms.csv',
              // cross_file reads `name` from the path; real drops carry one.
              path: 'terms.csv',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(settings.writes, 0);
      expect(
        find.byKey(const ValueKey('dictionary-term-import-select-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('dictionary-term-import-select-3')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('dictionary-term-import-select-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictionary-term-import-confirm')),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TermImportPage)),
      );
      // Imported terms become term entries (#1969); the term text itself
      // follows from the replacements and is not written here.
      final entries = await tester.runAsync(
        () => container.read(replacementsProvider.future),
      );
      expect(
        entries!
            .where((e) => e.triggers.single == e.replacement)
            .map((e) => e.replacement),
        ['Kubernetes'],
      );
      expect(settings.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
