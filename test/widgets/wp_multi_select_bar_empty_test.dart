// With select mode on and nothing ticked, the shared bar keeps its slots:
// Select All works, actions that need a selection are disabled and say why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_multi_select_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  Future<void> pump(WidgetTester tester, int selected, List<String> log) =>
      tester.pumpWidget(
        makeTestable(
          Scaffold(
            body: WpMultiSelectBar(
              selectedCount: selected,
              totalCount: 3,
              isTrashView: false,
              isArchiveView: false,
              onCancelSelection: () => log.add('cancel'),
              onSelectAll: () => log.add('all'),
              onExport: () => log.add('export'),
              onDelete: () => log.add('delete'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );

  testWidgets('0 selected: delete and menu disabled with a reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final l10n = await L10n.delegate.load(const Locale('en'));
    final log = <String>[];
    await pump(tester, 0, log);
    await tester.pumpAndSettle();

    final delete = tester.widget<WpMultiSelectAction>(
      find.byKey(const ValueKey('history-multiselect-delete')),
    );
    expect(delete.onTap, isNull);
    expect(delete.disabledReason, l10n.multiSelectNothingSelected);
    final more = tester.widget<PopupMenuButton<VoidCallback>>(
      find.byKey(const ValueKey('history-multiselect-more')),
    );
    expect(more.enabled, isFalse);
    expect(more.tooltip, l10n.multiSelectNothingSelected);

    await tester.tap(
      find.byKey(const ValueKey('history-multiselect-select-all')),
    );
    expect(log, ['all']);

    await pump(tester, 1, log);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WpMultiSelectAction>(
            find.byKey(const ValueKey('history-multiselect-delete')),
          )
          .onTap,
      isNotNull,
    );
  });
}
