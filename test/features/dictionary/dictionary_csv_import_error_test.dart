/// The CSV import needs the existing triggers to detect duplicates. When that
/// list failed to load, the import must stop with an error instead of
/// treating the list as empty (UIA-DIC-02).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_actions.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

class _BrokenReplacements extends ReplacementsNotifier {
  @override
  Future<List<Replacement>> build() => Future.error(StateError('db locked'));
}

void main() {
  testWidgets('import stops with an error when the existing list failed', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      makeTestable(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => importReplacementsCsv(context, ref),
              child: const Text('import'),
            ),
          ),
        ),
        locale: const Locale('en'),
        overrides: [replacementsProvider.overrideWith(_BrokenReplacements.new)],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.errorGeneric), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });
}
