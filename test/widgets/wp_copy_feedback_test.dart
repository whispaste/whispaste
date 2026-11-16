/// What a copy triggers: the clipboard write, the mark at its target, the
/// screen reader announcement and the telemetry count. Not how it looks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_copy_feedback.dart';

import '../fixtures/test_helpers.dart';

void main() {
  const note = ValueKey('copy-note-row-1');
  const otherNote = ValueKey('copy-note-row-2');
  const host = ValueKey('host');
  late List<String> written;
  late bool failing;

  setUp(() {
    written = [];
    failing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method != 'Clipboard.setData') return null;
          if (failing) throw PlatformException(code: 'clipboard-unavailable');
          written.add((call.arguments as Map)['text'] as String);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<L10n> pumpRows(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        const Column(
          key: host,
          children: [
            WpCopyAnchor(target: 'row-1', child: Text('one')),
            WpCopyAnchor(target: 'row-2', child: Text('two')),
          ],
        ),
        locale: const Locale('en'),
      ),
    );
    return L10n.delegate.load(const Locale('en'));
  }

  Future<void> copy(
    WidgetTester tester,
    String target, {
    String? category,
  }) async {
    await copyWithFeedback(
      tester.element(find.byKey(host)),
      text: 'text',
      target: target,
      category: category,
    );
    await tester.pump();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byKey(host)));

  testWidgets('the tenth copy of a row is a new confirmation, like the first', (
    tester,
  ) async {
    await pumpRows(tester);

    final seqs = <int>[];
    for (var i = 0; i < 10; i++) {
      await copy(tester, 'row-1');
      seqs.add(container(tester).read(copyMarkProvider)!.seq);
    }

    expect(seqs.toSet(), hasLength(10));
    expect(find.byKey(ValueKey('copy-note-pop-${seqs.last}')), findsOneWidget);
    expect(find.byKey(ValueKey('copy-note-pop-${seqs.first}')), findsNothing);
  });

  testWidgets('a duplicate answers at the row it came from', (tester) async {
    await pumpRows(tester);

    confirmAtTrigger(tester.element(find.byKey(host)), target: 'row-2');
    await tester.pump();

    expect(written, isEmpty);
    expect(find.byKey(otherNote), findsOneWidget);
    expect(find.byKey(note), findsNothing);
    expect(
      container(tester).read(copyMarkProvider)!.outcome,
      WpCopyOutcome.duplicated,
    );
  });

  testWidgets('a copy writes the clipboard and answers at its own row only', (
    tester,
  ) async {
    await pumpRows(tester);

    await copy(tester, 'row-1');

    expect(written, ['text']);
    expect(find.byKey(note), findsOneWidget);
    expect(find.byKey(otherNote), findsNothing);

    await tester.pump(WpCopyMarkNotifier.copiedFor);
    expect(find.byKey(note), findsNothing);
  });

  testWidgets('a new copy replaces the mark and its running time', (
    tester,
  ) async {
    await pumpRows(tester);

    await copy(tester, 'row-1');
    await tester.pump(const Duration(seconds: 1));
    await copy(tester, 'row-2');
    expect(find.byKey(note), findsNothing);
    expect(find.byKey(otherNote), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(otherNote), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(otherNote), findsNothing);
  });

  testWidgets('a failed copy stays longer and is announced with the way out', (
    tester,
  ) async {
    final l10n = await pumpRows(tester);
    failing = true;

    await copy(tester, 'row-1');

    expect(written, isEmpty);
    expect(tester.takeException(), isNull);
    expect(tester.takeAnnouncements().map((a) => a.message), [
      l10n.copyFailedHint,
    ]);
    await tester.pump(WpCopyMarkNotifier.copiedFor);
    expect(find.byKey(note), findsOneWidget);
    await tester.pump(WpCopyMarkNotifier.failedFor);
    expect(find.byKey(note), findsNothing);
  });

  testWidgets('a copy is announced to screen readers', (tester) async {
    final l10n = await pumpRows(tester);

    await copy(tester, 'row-1');

    expect(tester.takeAnnouncements().map((a) => a.message), [l10n.copyDone]);
    await tester.pump(WpCopyMarkNotifier.copiedFor);
  });

  testWidgets('only a named category reaches telemetry, and only on success', (
    tester,
  ) async {
    await pumpRows(tester);
    final counts = container(
      tester,
    ).read(telemetrySessionAggregatorProvider).debugCounts;

    await copy(tester, 'row-1');
    expect(
      container(tester).read(telemetrySessionAggregatorProvider).debugCounts,
      counts,
    );

    await copy(tester, 'row-1', category: 'history');
    expect(
      container(tester).read(telemetrySessionAggregatorProvider).debugCounts[(
        'history',
        'copy',
        null,
      )],
      1,
    );

    failing = true;
    await copy(tester, 'row-1', category: 'history');
    expect(
      container(tester).read(telemetrySessionAggregatorProvider).debugCounts[(
        'history',
        'copy',
        null,
      )],
      1,
    );
    await tester.pump(WpCopyMarkNotifier.failedFor);
  });

  group('WpCopyButton', () {
    Future<void> pumpButton(WidgetTester tester, VoidCallback onCopied) =>
        tester.pumpWidget(
          makeTestable(
            WpCopyButton(
              testId: 'copy-it',
              label: 'Copy',
              variant: WpButtonVariant.secondary,
              text: () async => 'built on click',
              onCopied: onCopied,
            ),
            locale: const Locale('en'),
          ),
        );

    Future<void> click(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('copy-it')));
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'a click copies, reports back and turns into the confirmation',
      (tester) async {
        var reported = 0;
        await pumpButton(tester, () => reported++);
        final l10n = await L10n.delegate.load(const Locale('en'));

        await click(tester);

        expect(written, ['built on click']);
        expect(reported, 1);
        expect(find.text(l10n.copyDone), findsOneWidget);
        // A success needs no second note beside the button.
        expect(find.byKey(const ValueKey('copy-note-copy-it')), findsNothing);

        await tester.pump(WpCopyMarkNotifier.copiedFor);
        expect(find.text(l10n.copyDone), findsNothing);
      },
    );

    testWidgets('a failure shows at the button and reports no success', (
      tester,
    ) async {
      var reported = 0;
      await pumpButton(tester, () => reported++);
      failing = true;

      await click(tester);

      expect(reported, 0);
      expect(find.byKey(const ValueKey('copy-note-copy-it')), findsOneWidget);
      await tester.pump(WpCopyMarkNotifier.failedFor);
    });
  });
}
