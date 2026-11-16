/// A page notice stays until it is closed, replaced or the page is left; an
/// error never closes itself, a confirmation does; a notice with an area shows
/// only there; each one is announced exactly once.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/onboarding_hold.dart';
import 'package:whispaste/widgets/wp_banner.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../fixtures/test_helpers.dart';

const _host = Key('host');

Finder _notice(String id) => find.byKey(ValueKey('page-notice-$id'));

void main() {
  Widget host({required bool showSlot}) => makeTestable(
    Builder(
      builder: (context) => Column(
        children: [
          if (showSlot) const WpPageNoticeSlot(page: 'demo'),
          TextButton(
            onPressed: () => showWpPageNotice(
              context,
              page: 'demo',
              notice: const WpPageNotice(
                id: 'result',
                message: '3 found',
                tone: WpBannerTone.info,
              ),
            ),
            child: const Text('result'),
          ),
          TextButton(
            onPressed: () => showWpPageNotice(
              context,
              page: 'demo',
              notice: const WpPageNotice(
                id: 'broken',
                message: 'Broken.',
                nextStep: 'Try again.',
              ),
            ),
            child: const Text('error'),
          ),
        ],
      ),
    ),
  );

  testWidgets('stays, is replaced, is closed and survives its slot', (
    tester,
  ) async {
    await tester.pumpWidget(host(showSlot: true));
    await tester.tap(find.text('result'));
    await tester.pump(const Duration(seconds: 60));
    expect(_notice('result'), findsOneWidget);

    await tester.tap(find.text('error'));
    await tester.pump();
    expect(_notice('result'), findsNothing);
    expect(find.text('Broken. Try again.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-notice-dismiss-demo')));
    await tester.pump();
    expect(_notice('broken'), findsNothing);

    await tester.tap(find.text('result'));
    await tester.pump();
    await tester.pumpWidget(host(showSlot: false));
    await tester.pump();
    await tester.pumpWidget(host(showSlot: true));
    expect(_notice('result'), findsOneWidget);
  });

  group('area', () {
    Future<BuildContext> pumpSlots(WidgetTester tester, {String? open}) async {
      await tester.pumpWidget(
        makeTestable(
          Column(
            key: _host,
            children: [
              WpPageNoticeSlot(page: 'p', openArea: open),
              const WpPageNoticeSlot(page: 'p', area: 'a'),
              const WpPageNoticeSlot(page: 'p', area: 'b'),
            ],
          ),
          locale: const Locale('en'),
        ),
      );
      return tester.element(find.byKey(_host));
    }

    testWidgets('shows once, in the slot of its area, and is announced once', (
      tester,
    ) async {
      final context = await pumpSlots(tester, open: 'a');
      showWpPageNotice(
        context,
        page: 'p',
        notice: const WpPageNotice(id: 'one', message: 'for a', area: 'a'),
      );
      await tester.pump();

      expect(_notice('one'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is WpPageNoticeSlot && w.area == 'a',
          ),
          matching: _notice('one'),
        ),
        findsOneWidget,
      );
      expect(
        tester.takeAnnouncements().where((a) => a.message == 'for a'),
        hasLength(1),
      );
    });

    testWidgets('a notice without area shows below the head only', (
      tester,
    ) async {
      final context = await pumpSlots(tester);
      showWpPageNotice(
        context,
        page: 'p',
        notice: const WpPageNotice(id: 'plain', message: 'x'),
      );
      await tester.pump();
      expect(_notice('plain'), findsOneWidget);
    });

    testWidgets('the head slot takes the notice of an area that is not open', (
      tester,
    ) async {
      final context = await pumpSlots(tester, open: 'b');
      showWpPageNotice(
        context,
        page: 'p',
        notice: const WpPageNotice(id: 'one', message: 'x', area: 'a'),
      );
      await tester.pump();
      // Head slot (area a is not open) and the area-a slot both show it.
      expect(_notice('one'), findsNWidgets(2));
    });

    testWidgets('the head slot leaves the notice to the open area', (
      tester,
    ) async {
      final context = await pumpSlots(tester, open: 'a');
      showWpPageNotice(
        context,
        page: 'p',
        notice: const WpPageNotice(id: 'one', message: 'x', area: 'a'),
      );
      await tester.pump();
      expect(_notice('one'), findsOneWidget);
    });

    testWidgets('pages do not share notices', (tester) async {
      final context = await pumpSlots(tester);
      showWpPageNotice(
        context,
        page: 'other',
        notice: const WpPageNotice(id: 'one', message: 'x'),
      );
      await tester.pump();
      expect(_notice('one'), findsNothing);
    });
  });

  group('autoDismiss', () {
    test('a confirmation closes itself, an error stays until closed', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = wpPageNoticeProvider('p');
        container.listen(provider, (_, _) {});
        final notifier = container.read(provider.notifier);

        notifier.show(
          const WpPageNotice(
            id: 'done',
            message: 'ok',
            autoDismiss: Duration(seconds: 4),
          ),
        );
        async.elapse(const Duration(seconds: 3));
        expect(container.read(provider), isNotNull);
        async.elapse(const Duration(seconds: 2));
        expect(container.read(provider), isNull);

        notifier.show(const WpPageNotice(id: 'failed', message: 'no'));
        async.elapse(const Duration(minutes: 5));
        expect(container.read(provider)?.id, 'failed');

        // A later confirmation does not push the open error out.
        notifier.show(
          const WpPageNotice(
            id: 'later',
            message: 'fine',
            tone: WpBannerTone.info,
            autoDismiss: Duration(seconds: 4),
          ),
        );
        expect(container.read(provider)?.id, 'failed');
      });
    });

    test('a newer confirmation restarts the timer', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = wpPageNoticeProvider('p');
        container.listen(provider, (_, _) {});
        final notifier = container.read(provider.notifier);
        const closeAfter = Duration(seconds: 4);

        notifier.show(
          const WpPageNotice(id: 'a', message: 'a', autoDismiss: closeAfter),
        );
        async.elapse(const Duration(seconds: 3));
        notifier.show(
          const WpPageNotice(id: 'b', message: 'b', autoDismiss: closeAfter),
        );
        async.elapse(const Duration(seconds: 1));
        // 4 s after A: A's timer would have fired, B must still be there.
        expect(container.read(provider)?.id, 'b');
        async.elapse(const Duration(seconds: 3));
        expect(container.read(provider), isNull);
      });
    });
  });

  testWidgets('an app error stands below the head until it is closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Column(
            children: [
              const WpAppErrorSlot(),
              TextButton(
                onPressed: () => showWpAppError(
                  context,
                  id: 'save-failed',
                  message: 'Not saved.',
                ),
                child: const Text('fail'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('fail'));
    await tester.pump(const Duration(seconds: 60));
    expect(_notice('save-failed'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('page-notice-dismiss-save-failed')),
    );
    await tester.pump();
    expect(_notice('save-failed'), findsNothing);
  });

  testWidgets('during onboarding the onboarding hold takes the app error', (
    tester,
  ) async {
    WpOnboardingHold.hold();
    addTearDown(WpOnboardingHold.release);
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showWpAppError(context, id: 'save-failed', message: 'x'),
            child: const Text('fail'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('fail'));
    await tester.pump();
    expect(WpOnboardingHold.held.value, hasLength(1));
    expect(_notice('save-failed'), findsNothing);
  });

  testWidgets('a second app error does not push out the first', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Column(
            children: [
              const WpAppErrorSlot(),
              TextButton(
                onPressed: () => showWpAppError(
                  context,
                  id: 'autosave-failed',
                  message: 'Backup failed.',
                ),
                child: const Text('backup'),
              ),
              TextButton(
                onPressed: () => showWpAppError(
                  context,
                  id: 'external-link-failed',
                  message: 'Link failed.',
                ),
                child: const Text('link'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('backup'));
    await tester.tap(find.text('link'));
    await tester.tap(find.text('link'));
    await tester.pump();
    expect(_notice('autosave-failed'), findsOneWidget);
    expect(_notice('external-link-failed'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('page-notice-dismiss-external-link-failed')),
    );
    await tester.pump();
    expect(_notice('external-link-failed'), findsNothing);
    expect(_notice('autosave-failed'), findsOneWidget);
  });

  testWidgets('closing a notice gives the focus back to where it was', (
    tester,
  ) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Column(
            children: [
              const WpPageNoticeSlot(page: 'demo'),
              TextField(focusNode: field),
              TextButton(
                onPressed: () => showWpPageNotice(
                  context,
                  page: 'demo',
                  notice: const WpPageNotice(id: 'broken', message: 'Broken.'),
                ),
                child: const Text('error'),
              ),
            ],
          ),
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TextField)),
    );
    showWpPageNotice(
      tester.element(find.byType(TextField)),
      page: 'demo',
      notice: const WpPageNotice(id: 'broken', message: 'Broken.'),
    );
    await tester.pump();
    expect(container.read(wpPageNoticeProvider('demo')), isNotNull);
    await tester.tap(find.byKey(const ValueKey('page-notice-dismiss-demo')));
    await tester.pump();
    await tester.pump();
    expect(_notice('broken'), findsNothing);
    expect(field.hasPrimaryFocus, isTrue);
  });

  test('the app errors hold at most three, the oldest goes first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(wpAppErrorsProvider.notifier);
    for (final id in ['a', 'b', 'c', 'd']) {
      notifier.add(WpPageNotice(id: id, message: id));
    }
    expect(container.read(wpAppErrorsProvider).map((e) => e.id), [
      'b',
      'c',
      'd',
    ]);
  });
}
