/// The draft of a write run waiting for the user's decision (#248).
///
/// Nothing reaches the target app before Enter: the draft waits here, Enter
/// (or the first button) pastes it through the regular paste path, Esc (or
/// the close button) drops it without inserting anything. A write run leaves
/// no history entry (ADR 0015 D12), so a dropped draft is gone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart'
    show SmartModeHotkeySettings;
import '../../../core/logging/app_logger.dart';
import '../../paste/paster.dart';
import '../../selection_edit/selection_edit_preview.dart'
    show selectionEditPasteOptions;

import 'smart_write_environment.dart';

final _log = AppLogger('SmartWritePreview');

/// Stable ids of the notices a write run shows, for the overlay, logs, tests.
const kSmartWritePreviewNoticeId = 'smart-write-preview';
const kSmartWriteHintNoSelectionNoticeId = 'smart-write-hint-no-selection';
const kSmartWritePresetMovedNoticeId = 'smart-write-preset-binding-moved';
const kSmartWriteRefineHintId = 'smart-write-refine-hint';
const kSmartWriteRefineLimitHintId = 'smart-write-refine-limit-hint';

/// testID of the preview line naming the snippet a draft is based on (#252).
const kSmartWriteSnippetLineId = 'smart-write-snippet-line';

/// Whether the one-time "preset binding moved" notice is due (D9): only for
/// an existing setup that had the Smart Mode hotkey on before the update and
/// has not seen it. Settings saved before the flag existed read it as false,
/// so they get the notice once; a fresh setup sets the flag when it turns the
/// hotkey on.
bool smartWritePresetMovedNoticeDue(SmartModeHotkeySettings settings) =>
    settings.smartModeHotkeyEnabled && !settings.smartWriteMigrationNoticeShown;

/// Refinement rounds one draft may go through by voice (#250): after the
/// third the preview asks to insert or discard, and the hotkey starts no
/// further recording.
const kSmartWriteMaxRefineRounds = 3;

@immutable
class SmartWriteDraft {
  const SmartWriteDraft({
    required this.text,
    required this.serial,
    this.target,
    this.targetChanged = false,
    this.wayland = false,
    this.errorCode,
    this.snippetTitle,
    this.snippetMissed = false,
    this.rounds = 0,
    this.edited = false,
    this.editorOpen = false,
    this.focusNotReturned = false,
  });

  final String text;
  final int serial;
  final String? target;
  final bool targetChanged;
  final bool wayland;
  final String? errorCode;

  /// Title of the snippet the draft is based on (#252); null without one.
  final String? snippetTitle;

  /// The instruction named a snippet, but none was used: the text was
  /// written freely (D11, no question asked).
  final bool snippetMissed;

  /// Successful refinements behind [text] (#250). It lives only with the
  /// draft in memory; a failed round leaves it as it was.
  final int rounds;

  /// Whether the user changed [text] in the edit field (D13, #254). [text]
  /// always holds what Enter inserts and what a refinement works on.
  final bool edited;

  /// Whether the preview shows the edit field instead of the plain text.
  final bool editorOpen;

  /// The last Enter could not hand the focus back to the target app (D13):
  /// nothing was inserted or copied, the draft waits with a hint.
  final bool focusNotReturned;

  /// Whether the refinement budget is spent ([kSmartWriteMaxRefineRounds]).
  bool get refineLimitReached => rounds >= kSmartWriteMaxRefineRounds;

  SmartWriteDraft copyWith({
    String? text,
    int? serial,
    String? target,
    bool? targetChanged,
    bool? edited,
    bool? editorOpen,
    bool? focusNotReturned,
  }) => SmartWriteDraft(
    text: text ?? this.text,
    serial: serial ?? this.serial,
    target: target ?? this.target,
    targetChanged: targetChanged ?? this.targetChanged,
    wayland: wayland,
    errorCode: errorCode,
    snippetTitle: snippetTitle,
    snippetMissed: snippetMissed,
    rounds: rounds,
    edited: edited ?? this.edited,
    editorOpen: editorOpen ?? this.editorOpen,
    focusNotReturned: focusNotReturned ?? this.focusNotReturned,
  );
}

class SmartWritePreviewNotifier extends Notifier<SmartWriteDraft?> {
  Timer? _timer;
  int _serial = 0;
  int _epoch = 0;

  /// Generation of the Enter/Esc grab: the field takes the keys and gives
  /// them back, and a late callback of an older grab does nothing.
  int _keyEpoch = 0;

  /// The edit field held the keyboard focus during this draft, so Enter
  /// must hand the focus back to the target app before it pastes (D13).
  bool _focusTaken = false;
  bool _busy = false;
  bool _editing = false;
  bool _keysRequested = false;
  Future<void> _releasing = Future<void>.value();
  bool _disposed = false;
  late SmartWriteEnvironment _environment;

  @override
  SmartWriteDraft? build() {
    _environment = ref.read(smartWriteEnvironmentProvider);
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _timer?.cancel();
      if (_keysRequested) unawaited(_environment.release());
    });
    return null;
  }

  Future<void> offer(
    String text, {
    SmartWriteDraft? previous,
    String? errorCode,
    String? snippetTitle,
    bool snippetMissed = false,
    int? rounds,
  }) async {
    discard();
    final epoch = _epoch;
    String? target;
    bool grabbed = false;
    try {
      await _releasing;
      if (epoch != _epoch) return;
      target = await _environment.target().timeout(const Duration(seconds: 5));
      if (epoch != _epoch) return;
      grabbed = await _grabKeys(epoch);
    } on Object catch (_) {
      _log.warning('Write preview preparation failed');
    }
    if (epoch != _epoch) return;
    if (!grabbed) {
      _releaseKeys();
      await _releasing;
      if (epoch != _epoch) return;
      await _copy(text, SmartWriteHint.keysFailed);
      return;
    }
    state = SmartWriteDraft(
      text: text,
      serial: ++_serial,
      target: previous != null ? previous.target : target,
      errorCode: errorCode,
      wayland: _environment.wayland,
      // A revision keeps what the first draft was based on.
      snippetTitle: previous != null ? previous.snippetTitle : snippetTitle,
      snippetMissed: previous != null ? previous.snippetMissed : snippetMissed,
      rounds: rounds ?? previous?.rounds ?? 0,
      // The new version replaces the edited text; the field stays open, so
      // editing goes on (#254). The card is redrawn and the field reports
      // its focus anew, which brings the focus gate back.
      editorOpen: previous?.editorOpen ?? false,
    );
    _armTimeout();
  }

  /// Registers Enter (insert) and Esc (discard) for the draft of [epoch].
  /// Each grab has its own key epoch: a callback of a grab the edit field
  /// replaced, or of an older draft, does nothing.
  Future<bool> _grabKeys(int epoch) {
    final keys = ++_keyEpoch;
    bool live() => epoch == _epoch && keys == _keyEpoch;
    _keysRequested = true;
    return _environment
        .grab(
          () {
            if (live()) unawaited(insert());
          },
          () {
            if (live()) discard();
          },
        )
        .timeout(const Duration(seconds: 5));
  }

  /// The edit field gained or lost the keyboard focus (#254, D21). While it
  /// has it, the session-wide Enter/Esc grabs are off, so Enter and Esc
  /// reach the field (Enter inserts, Shift+Enter breaks the line, Esc
  /// discards); the inactivity timer pauses. Leaving the field registers the
  /// grabs again and starts a fresh inactivity budget.
  void setEditingFocus(bool focused) {
    final changed = focused != _editing;
    _editing = focused;
    _armTimeout();
    if (!changed || state == null) return;
    if (focused) {
      _focusTaken = true;
      // Callbacks of the grab in place are dead from here on.
      _keyEpoch++;
      _releaseKeys();
    } else {
      unawaited(_regrabKeys());
    }
  }

  Future<void> _regrabKeys() async {
    final epoch = _epoch;
    final keys = ++_keyEpoch;
    await _releasing;
    if (epoch != _epoch || keys != _keyEpoch || _editing) return;
    var grabbed = false;
    try {
      grabbed = await _grabKeys(epoch);
    } on Object catch (e) {
      // Logged below as a missing grab.
      _log.debug('Key grab threw', e);
    }
    if (epoch != _epoch) return;
    if (!grabbed) {
      // The card's buttons still insert and discard.
      _log.warning('Write preview keys not registered again after editing');
    }
  }

  /// The edit toggle of the card: shows the field (#254).
  void openEditor() {
    final draft = state;
    if (draft == null || draft.editorOpen || draft.targetChanged) return;
    state = draft.copyWith(serial: ++_serial, editorOpen: true);
    _armTimeout();
  }

  /// The text in the edit field changed. Keeps the draft's serial, so the
  /// card is not drawn anew while the user types.
  void updateText(String text) {
    final draft = state;
    if (draft == null || draft.text == text) return;
    state = draft.copyWith(text: text, edited: true);
    _armTimeout();
  }

  /// Enter in the edit field: inserts [text], the text the field holds.
  Future<PasteOutcome?> submitEdited(String text) {
    updateText(text);
    return insert();
  }

  void noteActivity() => _armTimeout();

  void _armTimeout() {
    _timer?.cancel();
    if (_editing || state == null) return;
    _timer = Timer(const Duration(seconds: 90), () {
      final draft = state;
      if (draft == null) return;
      discard();
      if (draft.targetChanged) {
        unawaited(_copy(draft.text, SmartWriteHint.targetChanged));
      } else {
        ref
            .read(smartWriteNoticeProvider.notifier)
            .announce(SmartWriteHint.expired);
      }
    });
  }

  void discard() {
    _epoch++;
    _timer?.cancel();
    _editing = false;
    _focusTaken = false;
    _keyEpoch++;
    _releaseKeys();
    if (state == null) return;
    state = null;
    _log.info('Write preview discarded');
  }

  void _releaseKeys() {
    if (!_keysRequested) return;
    _keysRequested = false;
    _releasing = _environment.release();
  }

  Future<void> _copy(String text, SmartWriteHint reason) async {
    final epoch = _epoch;
    bool copied = false;
    try {
      copied = await _environment
          .copy(text)
          .timeout(const Duration(seconds: 5));
    } on Object catch (_) {
      _log.warning('Write clipboard fallback failed');
    }
    if (_disposed || epoch != _epoch) return;
    ref
        .read(smartWriteNoticeProvider.notifier)
        .announce(
          copied ? reason : SmartWriteHint.clipboardFailed,
          retainedText: copied ? null : text,
        );
  }

  /// Checks on every Enter, including the second confirmation. A further
  /// app switch needs another confirmation; Esc and timeout invalidate reads.
  Future<PasteOutcome?> insert() async {
    final draft = state;
    if (draft == null || _busy) return null;
    _busy = true;
    var pasteStarted = false;
    final epoch = _epoch;
    try {
      final paster = ref.read(pasterProvider);
      if (_focusTaken && !await _returnFocus(draft, epoch)) return null;
      if (epoch != _epoch) return null;
      if (!draft.wayland) {
        final front = await _environment.foreground().timeout(
          const Duration(seconds: 5),
        );
        if (epoch != _epoch) return null;
        if (front == null || front.isOwn || draft.target == null) {
          discard();
          await _copy(draft.text, SmartWriteHint.targetUnknown);
          return null;
        }
        if (front.id != draft.target) {
          state = draft.copyWith(
            serial: ++_serial,
            target: front.id,
            targetChanged: true,
            focusNotReturned: false,
          );
          _armTimeout();
          return null;
        }
        if (paster != null) {
          // A refinement may have primed another target. Capture only the
          // app just checked/confirmed, then verify the native capture too.
          await paster.prime().timeout(const Duration(seconds: 5));
          final captured = await _environment.target().timeout(
            const Duration(seconds: 5),
          );
          final checked = await _environment.foreground().timeout(
            const Duration(seconds: 5),
          );
          if (epoch != _epoch) return null;
          if (captured != draft.target ||
              checked?.id != draft.target ||
              checked?.isOwn != false) {
            discard();
            await _copy(draft.text, SmartWriteHint.targetChanged);
            return null;
          }
        }
      } else {
        _log.info('Write paste: target unverifiable on Wayland (D18 accepted)');
      }
      if (epoch != _epoch) return null;
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      discard();
      pasteStarted = true;
      final outcome =
          await paster?.paste(
            draft.text,
            selectionEditPasteOptions(settings),
          ) ??
          PasteOutcome.platformUnavailable;
      if (outcome != PasteOutcome.success) {
        await _copy(draft.text, SmartWriteHint.pasteFailed);
      }
      _log.info('Write preview inserted (outcome=${outcome.name})');
      return outcome;
    } on Object catch (_) {
      if (epoch == _epoch || pasteStarted) {
        if (!pasteStarted) discard();
        await _copy(draft.text, SmartWriteHint.pasteFailed);
      }
      return PasteOutcome.failed;
    } finally {
      _busy = false;
    }
  }

  /// The focus gate of an edited draft (D13): the edit field took the
  /// keyboard focus, so the target app gets it back before anything is
  /// pasted. Unconfirmed, nothing is inserted and nothing copied; the draft
  /// stays open with a hint, and the next Enter tries again. On Wayland the
  /// return cannot be checked: it pastes with the D18 hint the card carries.
  Future<bool> _returnFocus(SmartWriteDraft draft, int epoch) async {
    var returned = false;
    try {
      returned = await _environment
          .returnFocus(draft.target)
          .timeout(const Duration(seconds: 5));
    } on Object catch (_) {
      _log.warning('Write preview focus return failed');
    }
    if (epoch != _epoch) return false;
    if (returned) {
      _focusTaken = false;
      return true;
    }
    if (draft.wayland) {
      _log.info('Write paste: focus return unverifiable on Wayland (D18)');
      return true;
    }
    _log.info('Write preview kept: focus return unconfirmed');
    final current = state ?? draft;
    state = current.copyWith(serial: ++_serial, focusNotReturned: true);
    _armTimeout();
    return false;
  }
}

final smartWritePreviewProvider =
    NotifierProvider<SmartWritePreviewNotifier, SmartWriteDraft?>(
      SmartWritePreviewNotifier.new,
    );

/// A hint of the write route that is no error: the app shell shows it as a
/// short toast card, never a dialog.
enum SmartWriteHint {
  /// Nothing was selected, so a new text is written.
  noSelection,
  targetChanged,
  targetUnknown,
  pasteFailed,
  keysFailed,
  expired,
  clipboardFailed,

  /// The clipboard held no text (image, file) and could not be put back after
  /// the selection check.
  clipboardNotRestored,

  /// A write job of the automation API pasted its result (D22): the user
  /// sees that a text arrived without a preview, and from where.
  automationInserted,

  /// As [automationInserted], on Wayland where the target was not checked
  /// (D18).
  automationInsertedWayland,
}

@immutable
class SmartWriteNotice {
  const SmartWriteNotice({
    required this.hint,
    required this.serial,
    this.retainedText,
  });

  final SmartWriteHint hint;

  /// Last-resort visible recovery if even the clipboard is unavailable.
  final String? retainedText;
  final int serial;
}

class SmartWriteNoticeNotifier extends Notifier<SmartWriteNotice?> {
  @override
  SmartWriteNotice? build() => null;

  void noSelection() => announce(SmartWriteHint.noSelection);

  void clipboardNotRestored() => announce(SmartWriteHint.clipboardNotRestored);

  void announce(SmartWriteHint hint, {String? retainedText}) {
    state = SmartWriteNotice(
      hint: hint,
      serial: (state?.serial ?? 0) + 1,
      retainedText: retainedText,
    );
  }
}

final smartWriteNoticeProvider =
    NotifierProvider<SmartWriteNoticeNotifier, SmartWriteNotice?>(
      SmartWriteNoticeNotifier.new,
    );
