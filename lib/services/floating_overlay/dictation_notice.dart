/// What the dictation pipeline has to say outside a recording (#453).
///
/// Dictation runs in another app, so the main window is usually hidden: a
/// failed paste, a missing model or a GPU fallback reaches the user on the
/// overlay card, not in a toast. With the overlay switched off the same notice
/// shows as a banner in the main window ([kAppNoticePage]).
///
/// Every notice names its cause and, where there is one, the next step; its
/// buttons run a callback and close the card. A new recording closes a card
/// that is still open, so a notice never blocks the next dictation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/announce.dart';
import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/recording/recording_state.dart' show RecordingPhase;
import '../../core/theme/tokens.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import 'overlay_notice.dart';
import 'overlay_notice_rules.dart' show noticeFitsState;

/// How long a hint or confirmation stays at least. An error stays until it is
/// closed.
const Duration kDictationHintTime = Duration(seconds: 8);

/// How long a status or success notice with [text] stays on screen: a base
/// plus a reading allowance per character (#781), never shorter than
/// [kDictationHintTime] so a short line is not gone before it is seen.
Duration dictationNoticeTime(String text) {
  final read = Duration(milliseconds: 4000 + 40 * text.length);
  return read < kDictationHintTime ? kDictationHintTime : read;
}

/// One button of a [DictationNotice].
@immutable
class DictationNoticeAction {
  const DictationNoticeAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.confirmation,
  });

  /// What the button does, in kebab-case (`use-microphone`, `open-settings`):
  /// the testID suffix of the button, independent of its place and its text.
  final String id;
  final String label;
  final VoidCallback onPressed;

  /// Short line for the pill after the button ran, for an action whose effect
  /// is not visible by itself (download started, setting switched) (#781).
  final String? confirmation;
}

/// An editable text on a [DictationNotice] (#254, the write preview's edit
/// field). The card shows [text] with a toggle until [open]; then a
/// multi-line field holds it, with the [insertHint] line under it. Enter in
/// the field submits, Shift+Enter breaks the line, Esc cancels (D21).
@immutable
class DictationNoticeEdit {
  const DictationNoticeEdit({
    required this.key,
    required this.text,
    required this.open,
    required this.toggleLabel,
    required this.fieldLabel,
    required this.insertHint,
    required this.onOpen,
    required this.onChanged,
    required this.onFocus,
    required this.onSubmit,
    required this.onCancel,
  });

  /// Changes when the text is replaced from outside (a new version); the
  /// field keeps its caret while the key stays.
  final int key;
  final String text;
  final bool open;
  final String toggleLabel;

  /// The field's name for assistive technology.
  final String fieldLabel;
  final String insertHint;
  final VoidCallback onOpen;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onFocus;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  /// The wire form for the overlay card.
  OverlayNoticeEdit toOverlay() => OverlayNoticeEdit(
    key: key,
    text: text,
    open: open,
    toggleLabel: toggleLabel,
    fieldLabel: fieldLabel,
    insertHint: insertHint,
  );

  /// Runs [event] from the card on this edit.
  void handle(OverlayNoticeEditEvent event) {
    switch (event.kind) {
      case OverlayNoticeEditKind.open:
        onOpen();
      case OverlayNoticeEditKind.text:
        onChanged(event.text ?? text);
      case OverlayNoticeEditKind.focus:
        onFocus(event.focused ?? false);
      case OverlayNoticeEditKind.submit:
        onSubmit(event.text ?? text);
      case OverlayNoticeEditKind.cancel:
        onCancel();
    }
  }
}

/// A message for the overlay card: [cause] is the headline, [nextStep] the
/// optional second sentence. At most two [actions] fit on the card.
@immutable
class DictationNotice {
  const DictationNotice({
    required this.id,
    required this.cause,
    this.nextStep = '',
    this.detail = '',
    this.notes = const [],
    this.tone = OverlayNoticeTone.hint,
    this.actions = const [],
    this.autoDismiss,
    this.offersNewDictation = true,
    this.firstActionOnEnter = false,
    this.managesOwnKeys = false,
    this.onDismiss,
    this.edit,
  }) : assert(actions.length <= 2, 'The card has room for two buttons');

  /// Stable name of the situation, for logs and tests.
  final String id;
  final String cause;
  final String nextStep;

  /// An extra line below the message that can arrive after it (the device
  /// suggested for a silent microphone, #613). It shows whole, with a line
  /// break, and is read out on its own when it is the only thing that is new.
  final String detail;

  /// Quiet hint lines under the body, each with its own testID (#251: the
  /// local model's quality hint, #250: the refine hint of the write
  /// preview). They are not part of [message], so they are not read out as
  /// the news.
  final List<OverlayNoticeNote> notes;
  final OverlayNoticeTone tone;
  final List<DictationNoticeAction> actions;

  /// Closes the card after this time. Null keeps it until it is closed; an
  /// error and a card with a button always keep it (WCAG 2.2.1, #781), see
  /// [closesItself].
  final Duration? autoDismiss;

  /// Whether the card's footer may offer "hotkey: dictate again". False for a
  /// paste warning that did not come from a dictation (snippet picker, side
  /// panel, re-paste), where nothing was dictated (#1147).
  final bool offersNewDictation;

  /// Whether Enter runs the first button while the card stands, instead of
  /// the spare cancel key (Esc or F12, #585). The AI preview (#589) confirms
  /// with Enter like an input field; Esc still closes it.
  final bool firstActionOnEnter;

  /// Session registered its keys before showing and owns action dismissal.
  final bool managesOwnKeys;

  /// Runs when the user closes the card with its close button or the cancel
  /// key, not when a button, a new recording or another card replaces it.
  /// The AI preview (#589) discards its proposal here.
  final VoidCallback? onDismiss;

  /// An editable [detail] (#254); null for a card without a field.
  final DictationNoticeEdit? edit;

  /// The time after which the card closes itself, null when it stays until
  /// it is closed: errors and cards that offer a button never time out.
  Duration? get effectiveAutoDismiss =>
      tone == OverlayNoticeTone.error || actions.isNotEmpty
      ? null
      : autoDismiss;

  bool get closesItself => effectiveAutoDismiss != null;

  String get message => nextStep.isEmpty ? cause : '$cause $nextStep';

  /// The card or banner body: the second sentence and the [detail] line.
  /// An open edit field holds the detail itself.
  String get body => [
    nextStep,
    if (edit?.open != true) detail,
  ].where((t) => t.isNotEmpty).join('\n');
}

/// What a screen reader should hear when [notice] replaces the one that is
/// open ([previousId] with [previousMessage] and [previousDetail], null when
/// none is open) (#613): nothing when the same message shows again unchanged,
/// only the [DictationNotice.detail] when that is all that is new, otherwise
/// the whole notice.
String? dictationAnnouncement(
  DictationNotice notice, {
  String? previousId,
  String previousMessage = '',
  String previousDetail = '',
}) {
  final sameMessage =
      previousId == notice.id && previousMessage == notice.message;
  if (sameMessage && previousDetail == notice.detail) return null;
  if (sameMessage) {
    return notice.detail.isEmpty ? null : notice.detail;
  }
  return notice.detail.isEmpty
      ? notice.message
      : '${notice.message} ${notice.detail}';
}

class DictationNoticeNotifier extends Notifier<DictationNotice?> {
  Timer? _timer;

  @override
  DictationNotice? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(DictationNotice notice) {
    _timer?.cancel();
    state = notice;
    _arm(notice);
  }

  /// Starts the close timer over; the service calls it when a notice that
  /// waited for the end of a recording finally shows.
  void restartTimer() {
    _timer?.cancel();
    final notice = state;
    if (notice != null) _arm(notice);
  }

  void _arm(DictationNotice notice) {
    final after = notice.effectiveAutoDismiss;
    if (after != null) {
      _timer = Timer(after, () {
        if (state == notice) state = null;
      });
    }
  }

  void dismiss() {
    _timer?.cancel();
    if (state != null) state = null;
  }

  /// Closes the open card when it no longer fits [phase] and [pipelineBusy]
  /// ([noticeFitsState]), so a "still busy" card goes once the app is ready
  /// (#1195). Returns whether it closed one.
  bool dismissIfStale({
    required RecordingPhase phase,
    required bool pipelineBusy,
  }) {
    final notice = state;
    if (notice == null ||
        noticeFitsState(
          noticeId: notice.id,
          phase: phase,
          pipelineBusy: pipelineBusy,
        )) {
      return false;
    }
    dismiss();
    return true;
  }
}

/// Closes a busy card that no longer fits, on the overlay and on the main
/// window banner that stands in for it while the overlay is off (#1195).
void dismissStaleDictationNotices(
  Ref ref, {
  required RecordingPhase phase,
  required bool pipelineBusy,
}) {
  ref
      .read(dictationNoticeProvider.notifier)
      .dismissIfStale(phase: phase, pipelineBusy: pipelineBusy);
  final banner = ref.read(wpPageNoticeProvider(kAppNoticePage));
  final id = banner?.id;
  if (id != null &&
      id.startsWith(_bannerNoticePrefix) &&
      !noticeFitsState(
        noticeId: id.substring(_bannerNoticePrefix.length),
        phase: phase,
        pipelineBusy: pipelineBusy,
      )) {
    ref.read(wpPageNoticeProvider(kAppNoticePage).notifier).dismiss();
  }
}

/// The notice the overlay card shows right now.
final dictationNoticeProvider =
    NotifierProvider<DictationNoticeNotifier, DictationNotice?>(
      DictationNoticeNotifier.new,
    );

/// Page id of the main window banner, used while the overlay is off.
const kAppNoticePage = kWpAppNoticePage;

/// Puts [notice] where the user looks while dictating: the overlay card, or
/// the main window banner when the overlay is off. The text is read out
/// either way, but a notice that replaces an open one with the same id and
/// text is not read again; a new [DictationNotice.detail] alone is (#613).
void showDictationNotice(BuildContext context, DictationNotice notice) {
  final container = ProviderScope.containerOf(context, listen: false);
  final view = View.of(context);
  final direction = Directionality.of(context);
  // Settings that are not loaded yet count as the default: overlay on.
  final overlayOn =
      container.read(settingsProvider).value?.effectiveOverlayMode !=
      OverlayMode.off;
  final String? spoken;
  if (overlayOn) {
    final open = container.read(dictationNoticeProvider);
    spoken = dictationAnnouncement(
      notice,
      previousId: open?.id,
      previousMessage: open?.message ?? '',
      previousDetail: open?.detail ?? '',
    );
    container.read(dictationNoticeProvider.notifier).show(notice);
  } else {
    final notifier = container.read(
      wpPageNoticeProvider(kAppNoticePage).notifier,
    );
    final open = container.read(wpPageNoticeProvider(kAppNoticePage));
    // The banner carries the detail as its second line.
    final shown = open?.message ?? '';
    final cut = shown.indexOf('\n');
    spoken = dictationAnnouncement(
      notice,
      previousId: open?.id == _bannerNoticeId(notice.id) ? notice.id : null,
      previousMessage: cut < 0 ? shown : shown.substring(0, cut),
      previousDetail: cut < 0 ? '' : shown.substring(cut + 1),
    );
    notifier.show(
      dictationBannerFor(notice, notifier.dismiss, showNotice: notifier.show),
    );
  }
  if (spoken != null) announce(view, spoken, direction);
}

const _bannerNoticePrefix = 'dictation-';

String _bannerNoticeId(String id) => '$_bannerNoticePrefix$id';

/// Whether the notice [id] still stands, on the overlay card or on the main
/// window banner that replaces it while the overlay is off.
bool dictationNoticeStands(Ref ref, String id) =>
    ref.read(dictationNoticeProvider)?.id == id ||
    ref.read(wpPageNoticeProvider(kAppNoticePage))?.id == _bannerNoticeId(id);

/// The main window banner for [notice]; [dismiss] closes it again. Shared by
/// the overlay-off path above and by the service, which falls back to it when
/// the overlay cannot show a notice. After a button with a
/// [DictationNoticeAction.confirmation] ran, the banner is replaced by that
/// confirmation through [showNotice], as the card does on the pill (#781).
WpPageNotice dictationBannerFor(
  DictationNotice notice,
  VoidCallback dismiss, {
  void Function(WpPageNotice)? showNotice,
}) {
  return WpPageNotice(
    id: _bannerNoticeId(notice.id),
    message: [
      notice.message,
      // An open edit field holds the detail itself (#254).
      if (notice.edit?.open != true) notice.detail,
      for (final n in notice.notes) n.text,
    ].where((t) => t.isNotEmpty).join('\n'),
    tone: notice.tone == OverlayNoticeTone.error
        ? WpBannerTone.error
        : WpBannerTone.info,
    autoDismiss: notice.effectiveAutoDismiss,
    action: notice.actions.isEmpty
        ? null
        // A Wrap, not a Row: at a large system text size the two buttons break
        // onto a second line instead of overflowing (#828).
        : (context) => _withBannerEdit(
            notice.edit,
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xs,
              children: [
                if (notice.edit case final edit? when !edit.open)
                  WpButton(
                    testId: kNoticeEditToggleId,
                    label: edit.toggleLabel,
                    variant: WpButtonVariant.ghost,
                    onPressed: edit.onOpen,
                  ),
                for (final (i, a) in notice.actions.indexed) ...[
                  // Same hierarchy as the card: first filled, second outlined.
                  WpButton(
                    testId: 'dictation-notice-action-${a.id}',
                    label: a.label,
                    variant: i == 0
                        ? WpButtonVariant.primary
                        : WpButtonVariant.secondary,
                    onPressed: () {
                      a.onPressed();
                      if (!notice.managesOwnKeys) dismiss();
                      final confirmation = a.confirmation;
                      if (confirmation != null && showNotice != null) {
                        showNotice(
                          WpPageNotice(
                            id: _bannerNoticeId('${notice.id}-confirmation'),
                            message: confirmation,
                            tone: WpBannerTone.info,
                            autoDismiss: kDictationHintTime,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
  );
}

/// The banner's buttons [buttons] with the open edit field of [edit] above
/// them (#254): the main window stands in for the overlay card while the
/// overlay is off, with the same keys (D21).
Widget _withBannerEdit(DictationNoticeEdit? edit, Widget buttons) {
  if (edit == null || !edit.open) return buttons;
  return SizedBox(
    width: 420,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DictationNoticeEditField(key: ValueKey(edit.key), edit: edit),
        const SizedBox(height: WpSpacing.xs),
        Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
      ],
    ),
  );
}

/// The edit field of a notice in the main window (#254, D21): Enter submits
/// the text as it stands, Shift+Enter breaks the line, Esc cancels. The
/// hint line under it names the keys (R25).
class DictationNoticeEditField extends StatefulWidget {
  const DictationNoticeEditField({super.key, required this.edit});

  final DictationNoticeEdit edit;

  @override
  State<DictationNoticeEditField> createState() =>
      _DictationNoticeEditFieldState();
}

class _DictationNoticeEditFieldState extends State<DictationNoticeEditField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.edit.text,
  );
  late final FocusNode _focus = FocusNode(
    debugLabel: kNoticeEditFieldId,
    onKeyEvent: _onKey,
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() => widget.edit.onFocus(_focus.hasFocus);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.edit.onCancel();
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      final value = _controller.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final text = value.text.replaceRange(
        selection.start,
        selection.end,
        '\n',
      );
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: selection.start + 1),
      );
      widget.edit.onChanged(text);
    } else if (event is KeyDownEvent) {
      widget.edit.onSubmit(_controller.text);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WpTextField(
        controller: _controller,
        focusNode: _focus,
        variant: WpTextFieldVariant.passage,
        testId: kNoticeEditFieldId,
        semanticsLabel: widget.edit.fieldLabel,
        autofocus: true,
        minLines: 3,
        maxLines: kNoticeEditFieldLines,
        keyboardType: TextInputType.multiline,
        onChanged: widget.edit.onChanged,
      ),
      const SizedBox(height: WpSpacing.xxs),
      Semantics(
        identifier: kNoticeEditInsertHintId,
        child: Text(
          widget.edit.insertHint,
          key: const ValueKey(kNoticeEditInsertHintId),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

/// The wire card for [notice]: its actions become `notice_1` / `notice_2`
/// and a close button, which the service resolves against [notice]. With
/// [actionKey] each button names the key that runs it: one press the first
/// (#585), two quick presses the second (#816).
OverlayNotice overlayNoticeFor(
  DictationNotice notice,
  L10n l10n, {
  String? actionKey,
}) {
  const ids = [OverlayNoticeActionId.notice1, OverlayNoticeActionId.notice2];
  return OverlayNotice(
    kind: OverlayNoticeKind.message,
    tone: notice.tone,
    title: notice.cause,
    body: notice.body,
    notes: notice.notes,
    edit: notice.edit?.toOverlay(),
    actions: [
      for (final (i, a) in notice.actions.indexed)
        OverlayNoticeAction(
          action: ids[i],
          name: a.id,
          label: a.label,
          keyHint: actionKey == null
              ? null
              : i == 0
              ? actionKey
              : notice.managesOwnKeys
              ? 'Esc'
              : '2× $actionKey',
          primary: i == 0,
        ),
      OverlayNoticeAction(
        action: OverlayNoticeActionId.dismiss,
        label: l10n.overlayNoticeDismiss,
      ),
    ],
  );
}
