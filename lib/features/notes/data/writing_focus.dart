/// Focus mode of the note editor (#669): a calm writing view that hides the
/// app frame and the note list, fills the screen and can dim every paragraph
/// but the one being written.
///
/// Pure logic plus two small notifiers; the window itself is reached through
/// [WindowFullScreen] so tests run without a native window.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:whispaste/core/config/command_shortcut.dart';
import 'package:whispaste/core/data/database.dart' show historyDatabaseProvider;
import 'package:whispaste/core/l10n/generated/app_localizations.dart' show L10n;
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/features/notes/blocks/long_note_layout.dart';

final _log = AppLogger('WritingFocus');

/// Keyboard shortcut that enters and leaves focus mode: Cmd/Ctrl+Shift+Enter.
SingleActivator writingFocusActivator({bool? isMacOS}) =>
    commandActivator(LogicalKeyboardKey.enter, shift: true, isMacOS: isMacOS);

/// [writingFocusActivator] as the user reads it: `⇧⌘↩` / `Ctrl+Shift+Enter`.
String writingFocusShortcutLabel(L10n? l10n, {bool? isMacOS}) =>
    commandShortcutLabel(enterKey, shift: true, isMacOS: isMacOS, l10n: l10n);

/// The paragraph around [offset] in [text] as the note's display rows define
/// it — the same unit "Go to paragraph" jumps between, so the lit paragraph
/// and the jump target always agree. Separators between paragraphs belong to
/// no paragraph; an offset inside one lights the paragraph before it.
TextRange focusParagraphRange(String text, int offset) {
  if (text.isEmpty) return const TextRange(start: 0, end: 0);
  final rows = NoteRows.of(text);
  final row = rows.rowOf(offset.clamp(0, text.length));
  return TextRange(
    start: rows.segmentStart(row),
    end: rows.segmentEnd(row, text.length),
  );
}

/// The window's full-screen switch, abstracted for tests.
abstract interface class WindowFullScreen {
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool value);
}

class _WindowManagerFullScreen implements WindowFullScreen {
  const _WindowManagerFullScreen();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
}

final windowFullScreenProvider = Provider<WindowFullScreen>(
  (ref) => const _WindowManagerFullScreen(),
);

/// Whether focus mode is on. Not remembered: every start opens the normal
/// view, focus mode is a deliberate step for one writing session.
class WritingFocusNotifier extends Notifier<bool> {
  /// Whether entering made the window full screen. Only then does leaving
  /// restore it — a window the user had already put full screen stays so.
  bool _setFullScreen = false;

  @override
  bool build() => false;

  Future<void> toggle() => state ? exit() : enter();

  Future<void> enter() async {
    if (state) return;
    state = true;
    final window = ref.read(windowFullScreenProvider);
    try {
      if (!await window.isFullScreen()) {
        await window.setFullScreen(true);
        _setFullScreen = true;
      }
    } on Object catch (e, st) {
      // Focus mode still works inside the window; only the full screen failed.
      _log.warning('Could not enter full screen', e, st);
    }
  }

  Future<void> exit() async {
    if (!state) return;
    state = false;
    if (!_setFullScreen) return;
    _setFullScreen = false;
    try {
      await ref.read(windowFullScreenProvider).setFullScreen(false);
    } on Object catch (e, st) {
      _log.warning('Could not leave full screen', e, st);
    }
  }
}

final writingFocusProvider = NotifierProvider<WritingFocusNotifier, bool>(
  WritingFocusNotifier.new,
);

/// Whether focus mode dims every paragraph but the current one. Off until the
/// user turns it on, then remembered: dimmed text surprises a first-time
/// user, but whoever chose it wants it again next time.
class ParagraphFocusNotifier extends AsyncNotifier<bool> {
  static const _key = 'notes_paragraph_focus';

  @override
  Future<bool> build() async {
    final raw = await ref.read(historyDatabaseProvider).readAppSetting(_key);
    return raw == '1';
  }

  Future<void> toggle() async {
    final next = !(state.value ?? false);
    state = AsyncData(next);
    try {
      await ref
          .read(historyDatabaseProvider)
          .writeAppSetting(_key, next ? '1' : '0');
    } on Object catch (e, st) {
      _log.warning('Could not save the paragraph focus', e, st);
    }
  }
}

final paragraphFocusProvider =
    AsyncNotifierProvider<ParagraphFocusNotifier, bool>(
      ParagraphFocusNotifier.new,
    );

/// Whether the editor dims every paragraph but the caret's right now: focus
/// mode is on and the user chose paragraph focus.
final paragraphDimProvider = Provider<bool>(
  (ref) =>
      ref.watch(writingFocusProvider) &&
      (ref.watch(paragraphFocusProvider).value ?? false),
);
