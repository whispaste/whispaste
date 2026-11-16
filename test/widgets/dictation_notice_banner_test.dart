/// #599: with the overlay off, a dictation message is not lost. It stands as a
/// banner in the main window, its button acts and closes it, and the overlay
/// card stays untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../fixtures/test_helpers.dart';

class _OverlayOffSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(overlayMode: OverlayMode.off.value);
}

void main() {
  testWidgets('with the overlay off the message shows as a banner and acts', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      makeTestable(
        Column(
          children: [
            const WpPageNoticeSlot(page: kAppNoticePage),
            Builder(
              builder: (context) => TextButton(
                key: const Key('fire'),
                onPressed: () => showDictationNotice(
                  context,
                  DictationNotice(
                    id: 'paste-failed',
                    cause: 'Paste failed',
                    nextStep: 'Press the paste shortcut',
                    tone: OverlayNoticeTone.error,
                    actions: [
                      DictationNoticeAction(
                        id: 'open-settings',
                        label: 'Open',
                        onPressed: () => opened++,
                      ),
                    ],
                  ),
                ),
                child: const Text('fire'),
              ),
            ),
          ],
        ),
        locale: const Locale('en'),
        overrides: [settingsProvider.overrideWith(_OverlayOffSettings.new)],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('fire'))),
    );
    // The settings load asynchronously; until they have, the overlay counts
    // as on.
    container.listen(settingsProvider, (_, _) {});
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('fire')));
    await tester.pump();
    expect(container.read(dictationNoticeProvider), isNull);
    expect(
      container.read(wpPageNoticeProvider(kAppNoticePage))?.id,
      'dictation-paste-failed',
    );

    await tester.tap(
      find.byKey(const ValueKey('dictation-notice-action-open-settings')),
    );
    await tester.pump();
    expect(opened, 1);
    expect(container.read(wpPageNoticeProvider(kAppNoticePage)), isNull);
  });

  testWidgets(
    'a suggestion that arrives later is read out alone in the banner',
    (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              const WpPageNoticeSlot(page: kAppNoticePage),
              Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(_OverlayOffSettings.new)],
        ),
      );
      final container = ProviderScope.containerOf(ctx);
      container.listen(settingsProvider, (_, _) {});
      await tester.pump();
      await tester.pump();
      DictationNotice notice({String detail = ''}) => DictationNotice(
        id: 'recording_guard_failed',
        cause: 'No audio detected.',
        detail: detail,
        tone: OverlayNoticeTone.error,
      );
      List<String> heard() =>
          tester.takeAnnouncements().map((a) => a.message).toList();

      showDictationNotice(ctx, notice());
      await tester.pump();
      expect(heard(), ['No audio detected.']);

      showDictationNotice(ctx, notice(detail: 'Suggestion: Blue Yeti'));
      await tester.pump();
      expect(heard(), ['Suggestion: Blue Yeti']);

      showDictationNotice(ctx, notice(detail: 'Suggestion: Blue Yeti'));
      await tester.pump();
      expect(heard(), isEmpty);
      // The banner carries the suggestion as its own line.
      expect(
        container.read(wpPageNoticeProvider(kAppNoticePage))?.message,
        'No audio detected.\nSuggestion: Blue Yeti',
      );
    },
  );
}
