/// Card-wide rules of the overlay notice card (#781): at most two text buttons
/// plus the cross, never a text button "Close", a cross that only hides the
/// card (labelled "Hide hint" over a recording), the footer of valid keys
/// and a close time that fits the text length. Logic only, no layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart'
    show activeTriggerLabel, formatHotkeyShortcut, singleKeyCap;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart'
    show RecordingPhase;
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/audio_service.dart'
    show RecordingStartFailure;
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice_rules.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  /// Every fixed card the rules can produce.
  List<OverlayNotice> allCards({bool canExtend = true}) => [
    noticeFor(
      state: OverlayVisualState.error,
      l10n: l10n,
      errorCode: RecordingStartFailure.noMicrophone.errorCode,
    )!,
    noticeFor(
      state: OverlayVisualState.error,
      l10n: l10n,
      errorCode: RecordingStartFailure.startFailed.errorCode,
    )!,
    noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      signalLost: true,
    )!,
    noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      remaining: '0:20',
      canExtend: canExtend,
    )!,
    noticeFor(state: OverlayVisualState.recording, l10n: l10n, quiet: true)!,
  ];

  group('buttons and cross', () {
    test('at most two text buttons, exactly one cross, no text "Close"', () {
      for (final card in [...allCards(), ...allCards(canExtend: false)]) {
        final buttons = card.actions.where((a) => !a.action.isClose).toList();
        final crosses = card.actions.where((a) => a.action.isClose).toList();
        expect(buttons.length, lessThanOrEqualTo(2), reason: card.kind.name);
        expect(crosses, hasLength(1), reason: card.kind.name);
        for (final b in buttons) {
          expect(b.label, isNot(l10n.overlayNoticeDismiss));
          expect(b.label, isNot(l10n.actionDismiss));
        }
      }
    });

    test('over a recording the cross is called "Hide hint"', () {
      for (final card in allCards().skip(2)) {
        final cross = card.actions.firstWhere((a) => a.action.isClose);
        expect(cross.label, l10n.overlayNoticeHideHint);
      }
    });

    test('a hidden kind stays away; the other kinds still show', () {
      OverlayNotice? card(Set<OverlayNoticeKind> hidden) => noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        signalLost: true,
        quiet: true,
        remaining: '0:20',
        hiddenKinds: hidden,
      );
      expect(card({})!.kind, OverlayNoticeKind.signalLost);
      expect(
        card({OverlayNoticeKind.signalLost})!.kind,
        OverlayNoticeKind.timeRunningOut,
      );
      expect(
        card({
          OverlayNoticeKind.signalLost,
          OverlayNoticeKind.timeRunningOut,
        })!.kind,
        OverlayNoticeKind.quiet,
      );
      expect(
        card({
          OverlayNoticeKind.signalLost,
          OverlayNoticeKind.timeRunningOut,
          OverlayNoticeKind.quiet,
        }),
        isNull,
      );
    });
  });

  group('footer', () {
    test('during a dictation: hotkey ends it, the cancel key discards', () {
      final text = noticeFooterFor(
        l10n: l10n,
        phase: NoticeFooterPhase.recording,
        hotkey: 'Ctrl+Space',
        cancelKey: 'Esc',
      );
      expect(text, contains('Ctrl+Space'));
      expect(text, contains('Esc'));
    });

    test(
      'without a dictation the hotkey dictates again, the cancel key closes',
      () {
        final text = noticeFooterFor(
          l10n: l10n,
          phase: NoticeFooterPhase.idle,
          hotkey: 'Ctrl+Space',
          cancelKey: 'Esc',
        );
        expect(text, contains('Ctrl+Space'));
        expect(text, contains('Esc'));
        expect(
          text,
          contains(l10n.overlayNoticeFooterIdle('Ctrl+Space', 'Esc')),
        );
      },
    );

    test('while the text is processed only the cancel key is offered', () {
      // The hotkey does nothing in this phase (#984), so it is not named.
      final text = noticeFooterFor(
        l10n: l10n,
        phase: NoticeFooterPhase.processing,
        hotkey: 'Ctrl+Space',
        cancelKey: 'Esc',
      );
      expect(text, l10n.overlayNoticeFooterProcessing('Esc'));
      expect(text, isNot(contains('Ctrl+Space')));
    });

    test('the footer leaves the button keys to the buttons (#1845)', () {
      // The buttons carry their own key ("Open (F12)"); the footer names only
      // the keys no button shows, so it stays short enough to read.
      final footer = noticeFooterFor(
        l10n: l10n,
        phase: NoticeFooterPhase.idle,
        hotkey: 'Ctrl+Space',
        cancelKey: 'Esc',
      );
      expect(footer, l10n.overlayNoticeFooterIdle('Ctrl+Space', 'Esc'));
      expect(footer, isNot(contains('F12')));
    });

    test('presses of the action key map to the buttons', () {
      expect(
        [
          for (final (presses, buttons) in [(1, 1), (2, 1), (1, 2), (2, 2)])
            noticeActionForPresses(presses: presses, buttons: buttons),
        ],
        [
          OverlayNoticeActionId.notice1,
          OverlayNoticeActionId.notice1,
          OverlayNoticeActionId.notice1,
          OverlayNoticeActionId.notice2,
        ],
      );
    });

    test('the footer survives the render channel', () {
      final card = allCards().first.withFooter('Ctrl+Space: dictate again');
      expect(OverlayNotice.fromMap(card.toMap())!.footer, card.footer);
    });
  });

  group('close time', () {
    test('a short line stays at least the minimum', () {
      expect(dictationNoticeTime('Saved'), kDictationHintTime);
    });

    test('a long text stays longer, in step with its length', () {
      final short = dictationNoticeTime('x' * 120);
      final long = dictationNoticeTime('x' * 300);
      expect(short, greaterThan(kDictationHintTime));
      expect(long, greaterThan(short));
    });
  });

  group('close rule', () {
    DictationNotice make({
      OverlayNoticeTone tone = OverlayNoticeTone.hint,
      bool action = false,
    }) => DictationNotice(
      id: 'x',
      cause: 'Cause',
      tone: tone,
      autoDismiss: const Duration(seconds: 8),
      actions: [
        if (action)
          DictationNoticeAction(id: 'a', label: 'A', onPressed: () {}),
      ],
    );

    test('only a pure status notice closes itself', () {
      expect(make().closesItself, isTrue);
      expect(make(action: true).closesItself, isFalse);
      expect(make(tone: OverlayNoticeTone.error).closesItself, isFalse);
    });

    test('the banner follows the same rule', () {
      expect(dictationBannerFor(make(), () {}).autoDismiss, isNotNull);
      expect(dictationBannerFor(make(action: true), () {}).autoDismiss, isNull);
    });
  });

  group('banner with the overlay off', () {
    testWidgets('shows both actions of the card', (tester) async {
      var first = 0;
      var second = 0;
      var closed = 0;
      final notice = DictationNotice(
        id: 'two',
        cause: 'Cause',
        actions: [
          DictationNoticeAction(
            id: 'one',
            label: 'One',
            onPressed: () => first++,
          ),
          DictationNoticeAction(
            id: 'two',
            label: 'Two',
            onPressed: () => second++,
          ),
        ],
      );
      final banner = dictationBannerFor(notice, () => closed++);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) => banner.action!(context)),
        ),
      );
      // Buttons are found by testID, never by label.
      expect(
        find.byKey(const ValueKey('dictation-notice-action-one')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('dictation-notice-action-two')),
        findsOne,
      );
      expect(first + second + closed, 0);
    });

    testWidgets(
      'an action with a confirmation shows it after the banner closes',
      (tester) async {
        final shown = <String>[];
        var closed = 0;
        final notice = DictationNotice(
          id: 'download',
          cause: 'Model missing',
          actions: [
            DictationNoticeAction(
              id: 'download',
              label: 'Download',
              onPressed: () {},
              confirmation: 'Downloading',
            ),
          ],
        );
        final banner = dictationBannerFor(
          notice,
          () => closed++,
          showNotice: (n) => shown.add(n.message),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Builder(builder: (context) => banner.action!(context)),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('dictation-notice-action-download')),
        );
        await tester.pump();
        expect(closed, 1);
        expect(shown, ['Downloading']);
      },
    );
  });

  group('footer ink', () {
    test('reaches 4.5:1 on the card body in every preset', () {
      for (final (bg, glassTone) in [
        for (final b in OverlayBackground.values)
          for (final t in OverlayDesignTheme.values) (b, t),
      ]) {
        final colors = OverlayDesignSpec.colorsFor(
          background: bg,
          glassTone: glassTone,
        );
        final ink = colors.noticeFooterInk;
        expect(
          contrastRatio(
            Color.alphaBlend(ink, colors.opaqueFill),
            colors.opaqueFill,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${bg.name} ${glassTone.name}',
        );
      }
    });
  });

  // #1195: a card never contradicts the state of the app.
  group('card content follows the app state', () {
    String footerAt(RecordingPhase phase) => noticeFooterFor(
      l10n: l10n,
      phase: noticeFooterPhaseFor(phase),
      hotkey: 'Ctrl+Space',
      cancelKey: 'Esc',
    );
    final dictating = l10n.overlayNoticeFooterDictating('Ctrl+Space', 'Esc');

    test('at rest no recording keys are offered', () {
      for (final phase in [
        RecordingPhase.idle,
        RecordingPhase.done,
        RecordingPhase.error,
      ]) {
        expect(noticeFooterPhaseFor(phase), NoticeFooterPhase.idle);
        expect(footerAt(phase), isNot(contains(dictating)), reason: '$phase');
      }
    });

    test('while recording the keys stop and discard', () {
      expect(
        noticeFooterPhaseFor(RecordingPhase.recording),
        NoticeFooterPhase.recording,
      );
      expect(footerAt(RecordingPhase.recording), contains(dictating));
    });

    test('while busy only discarding is offered', () {
      for (final phase in [
        RecordingPhase.transcribing,
        RecordingPhase.refining,
      ]) {
        expect(noticeFooterPhaseFor(phase), NoticeFooterPhase.processing);
        expect(footerAt(phase), isNot(contains('Ctrl+Space')));
      }
    });

    test('the busy card goes once the app is ready', () {
      expect(
        noticeFitsState(
          noticeId: kPipelineBusyNoticeId,
          phase: RecordingPhase.idle,
          pipelineBusy: false,
        ),
        isFalse,
      );
      expect(
        noticeFitsState(
          noticeId: kPipelineBusyNoticeId,
          phase: RecordingPhase.done,
          pipelineBusy: true,
        ),
        isTrue,
      );
      expect(
        noticeFitsState(
          noticeId: kPipelineBusyNoticeId,
          phase: RecordingPhase.transcribing,
          pipelineBusy: false,
        ),
        isTrue,
      );
    });

    test('"still processing" stands only while text is processed', () {
      for (final phase in RecordingPhase.values) {
        expect(
          noticeFitsState(
            noticeId: kStillProcessingNoticeId,
            phase: phase,
            pipelineBusy: true,
          ),
          phase == RecordingPhase.transcribing ||
              phase == RecordingPhase.refining,
          reason: '$phase',
        );
      }
    });

    test('other cards are not closed by the state', () {
      expect(
        noticeFitsState(
          noticeId: 'paste-failed',
          phase: RecordingPhase.idle,
          pipelineBusy: false,
        ),
        isTrue,
      );
    });
  });

  group('key hints name the trigger the user set', () {
    const combo = (key: 'space', modifiers: 'ctrl', display: '');
    AppSettings withSingle(String key) =>
        AppSettings(hotkey: HotkeySettings(hotkeyDoubleTapKey: key));

    test('a single key is named when it listens', () {
      expect(
        activeTriggerLabel(
          withSingle('rightAlt'),
          combo: combo,
          doubleTapFallback: false,
          l10n: l10n,
          isMacOS: false,
        ),
        l10n.settingsModifierRightAlt,
      );
    });

    test('the combination is named without a single key or in fallback', () {
      final expected = formatHotkeyShortcut(
        'ctrl',
        'space',
        l10n: l10n,
        isMacOS: false,
      );
      for (final (settings, fallback) in [
        (withSingle(''), false),
        (withSingle('rightAlt'), true),
      ]) {
        expect(
          activeTriggerLabel(
            settings,
            combo: combo,
            doubleTapFallback: fallback,
            l10n: l10n,
            isMacOS: false,
          ),
          expected,
        );
      }
    });

    test('the compact form is the key cap of the single key', () {
      expect(
        activeTriggerLabel(
          withSingle('rightAlt'),
          combo: combo,
          doubleTapFallback: false,
          l10n: l10n,
          compact: true,
          isMacOS: false,
        ),
        singleKeyCap(l10n, 'rightAlt', isMacOS: false).cap,
      );
    });
  });
}
