/// Feedback of the settings page: an error stands at the section that raised
/// it and stays until it is closed (#452); a short confirmation stands in the
/// notice bar at the bottom like every other and closes itself (#1903).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/features/settings/widgets/overlay_theme_swatches.dart';
import 'package:whispaste/features/settings/widgets/settings_notice.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';
import 'package:whispaste/widgets/wp_notice_bar.dart';

import '../../fixtures/test_helpers.dart';

const _dismiss = ValueKey('page-notice-dismiss-settings');

class _Settings extends SettingsNotifier {
  _Settings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;

  @override
  Future<void> updateSettings(
    AppSettings Function(AppSettings) update, {
    bool awaitPersist = false,
  }) async {
    state = AsyncData(update(_value));
  }
}

void main() {
  group('settings notice slot', () {
    Future<BuildContext> pumpGroups(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (c) {
              context = c;
              return const Column(
                children: [
                  WpSettingsGroup(
                    noticeArea: 'one',
                    children: [Text('row-one')],
                  ),
                  WpSettingsGroup(
                    noticeArea: 'two',
                    children: [Text('row-two')],
                  ),
                ],
              );
            },
          ),
          locale: const Locale('en'),
          noticeBar: true,
        ),
      );
      await tester.pumpAndSettle();
      return context;
    }

    testWidgets('an error shows in its own section only and stays until '
        'it is closed', (tester) async {
      final context = await pumpGroups(tester);

      showSettingsNotice(
        context,
        area: 'one',
        id: 'x',
        message: 'It failed. Try again.',
        failed: true,
      );
      await tester.pump();
      expect(find.text('It failed. Try again.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WpSettingsGroup).last,
          matching: find.text('It failed. Try again.'),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('It failed. Try again.'), findsOneWidget);

      await tester.tap(find.byKey(_dismiss));
      await tester.pump();
      expect(find.text('It failed. Try again.'), findsNothing);
    });

    testWidgets('a confirmation never pushes out an open error', (
      tester,
    ) async {
      final context = await pumpGroups(tester);

      showSettingsNotice(
        context,
        area: 'one',
        id: 'e',
        message: 'It failed',
        failed: true,
      );
      await tester.pump();
      showSettingsNotice(context, area: 'two', id: 'c', message: 'Done');
      await tester.pump();

      expect(find.text('It failed'), findsOneWidget);
      expect(_inBar('Done'), findsOneWidget);
      await tester.pump(kWpNoticeUndoMinimum);
      expect(find.text('It failed'), findsOneWidget);
    });

    testWidgets('a confirmation held back by an open error is announced '
        'without a banner (#557)', (tester) async {
      final context = await pumpGroups(tester);
      showSettingsNotice(
        context,
        area: 'one',
        id: 'e',
        message: 'It failed',
        failed: true,
      );
      await tester.pump();
      tester.takeAnnouncements();

      showSettingsNotice(context, area: 'two', id: 'c', message: 'Done');
      await tester.pump();

      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Done'),
      );
      expect(find.text('It failed'), findsOneWidget);
      await tester.pump(kWpNoticeUndoMinimum);
    });

    testWidgets('a confirmation stands in the notice bar at the bottom, '
        'not above the rows, and closes itself (#1903)', (tester) async {
      final context = await pumpGroups(tester);
      final rowTop = tester.getTopLeft(find.text('row-two')).dy;

      showSettingsNotice(context, area: 'one', id: 'a', message: 'Done A');
      await tester.pump();
      expect(_inBar('Done A'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WpSettingsGroup),
          matching: find.text('Done A'),
        ),
        findsNothing,
      );
      // The rows the user works on keep their place.
      expect(tester.getTopLeft(find.text('row-two')).dy, rowTop);

      await tester.pump(kWpNoticeUndoMinimum + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Done A'), findsNothing);
    });
  });

  testWidgets('a background pick that replaces the wave names both waves in '
      'the overlay section', (tester) async {
    // A wave that is not valid on a background it is moved to.
    OverlayWave? before;
    OverlayBackground? target;
    for (final wave in OverlayWave.values) {
      for (final bg in OverlayBackground.values) {
        if (!wave.isValidOn(bg) && target == null) {
          before = wave;
          target = bg;
        }
      }
    }
    final wave = before!;
    final background = target!;
    final settings = AppSettings.defaults.copyWith(overlayWave: wave.value);

    await tester.pumpWidget(
      makeTestable(
        Consumer(
          builder: (context, ref, _) => Column(
            children: [
              const WpSettingsGroup(
                noticeArea: 'overlay',
                children: [Text('colours')],
              ),
              TextButton(
                key: const ValueKey('pick'),
                onPressed: () =>
                    pickOverlayBackground(context, ref, settings, background),
                child: const Text('pick'),
              ),
            ],
          ),
        ),
        locale: const Locale('en'),
        overrides: [settingsProvider.overrideWith(() => _Settings(settings))],
        noticeBar: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pick')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('notice-bar-settings-wave-replaced')),
      findsOneWidget,
    );
    await tester.pump(kWpNoticeUndoMinimum);
  });
}

Finder _inBar(String text) =>
    find.descendant(of: find.byType(WpNoticeBar), matching: find.text(text));
