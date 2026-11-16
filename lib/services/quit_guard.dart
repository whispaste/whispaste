/// One gate for every interactive way to quit (tray, Cmd+Q / Dock, window
/// close with "close = quit"): while a dictation is recording or being
/// transcribed, the user confirms first (UIA-SHL-15, #1498). Signals
/// (SIGTERM/SIGINT) do not ask; they only save and rely on recovery.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_navigator.dart' show appNavigatorKey;
import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart';
import '../widgets/quit_during_dictation_dialog.dart';
import 'window_activation.dart';

class QuitGuard {
  QuitGuard({
    required this.isBusy,
    required this.showWindow,
    required this.ask,
  });

  final bool Function() isBusy;
  final Future<void> Function() showWindow;

  /// Shows the confirm dialog; true only when the user confirms the quit.
  final Future<bool> Function() ask;

  Future<bool>? _pending;

  /// True when the quit may proceed: nothing is running, or the user
  /// confirmed. A second request while the dialog is open joins it.
  Future<bool> allowQuit() {
    if (!isBusy()) return Future.value(true);
    return _pending ??= _confirm().whenComplete(() => _pending = null);
  }

  Future<bool> _confirm() async {
    try {
      await showWindow();
      return await ask();
    } on Object {
      // Cannot ask: protecting the dictation wins over quitting.
      return false;
    }
  }
}

final quitGuardProvider = Provider<QuitGuard>(
  (ref) => QuitGuard(
    isBusy: () => isDictationBusy(ref.read(recordingProvider).phase),
    showWindow: () => ref.read(windowActivatorProvider)(),
    ask: () async {
      final context = appNavigatorKey.currentContext;
      if (context == null) return false;
      return showWpQuitDuringDictationDialog(
        context: context,
        l10n: L10n.of(context),
      );
    },
  ),
);

/// Reply to the native macOS `confirmTermination` (Cmd+Q / Dock Quit): true =
/// quit may go on, false = the user cancelled during a dictation and the app
/// stays open (#1498). main.dart hands it to
/// `MacOSLifecycleChannel.registerTerminationHandler`.
Future<bool> answerConfirmTermination(ProviderContainer container) =>
    container.read(quitGuardProvider).allowQuit();
