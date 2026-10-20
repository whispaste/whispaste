/// Holds one pending multiline paste for the main-window preview (WP-38 /
/// 8.5).
///
/// An automation call that would insert multiline text waits here until the
/// user confirms or cancels in the preview. Nothing is inserted by this
/// file. Only one request may be open at a time; a second one is refused
/// straight away rather than queued, so a script cannot stack up pastes.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a preview waits for the user before it cancels itself.
const kMultilinePasteConfirmTimeout = Duration(seconds: 60);

/// How long an API-triggered preview waits (WP-43a A-M7). It stays below
/// [kAutomationClientTimeout] so the preview closes before the client gives up
/// and a late confirm cannot paste into an abandoned request.
const kAutomationPreviewWait = Duration(seconds: 12);

/// Whether [text] must be previewed before it is handed to the paste path.
bool needsMultilinePreview(String text) => _lineBreak.hasMatch(text);

/// LF, CR, VT, FF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR (WP-43a A-N5).
final _lineBreak = RegExp('[\n\r\v\f\u0085\u2028\u2029]');

class MultilinePasteRequest {
  const MultilinePasteRequest({required this.text});

  final String text;

  /// Number of lines as the user sees them (`\r\n`, `\r` and `\n` all end
  /// a line).
  int get lineCount {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return '\n'.allMatches(normalized).length + 1;
  }
}

class MultilinePasteConfirmation extends Notifier<MultilinePasteRequest?> {
  Completer<bool>? _pending;
  Timer? _timeout;

  @override
  MultilinePasteRequest? build() {
    // Disposal must not write state: Riverpod forbids it inside a lifecycle
    // callback. Completing the pending request is enough.
    ref.onDispose(() => _complete(false));
    return null;
  }

  /// Shows [text] in the preview and completes with the user's decision:
  /// `true` only after an explicit confirm. Cancel, timeout, a second
  /// request, and disposal all complete with `false`.
  Future<bool> request(
    String text, {
    Duration timeout = kMultilinePasteConfirmTimeout,
  }) {
    if (_pending != null) return Future.value(false);

    final completer = Completer<bool>();
    _pending = completer;
    state = MultilinePasteRequest(text: text);
    _timeout = Timer(timeout, () => _settle(false));
    return completer.future;
  }

  void confirm() => _settle(true);

  void cancel() => _settle(false);

  void _settle(bool value) {
    if (_pending == null) return;
    state = null;
    _complete(value);
  }

  void _complete(bool value) {
    final completer = _pending;
    if (completer == null) return;
    _pending = null;
    _timeout?.cancel();
    _timeout = null;
    if (!completer.isCompleted) completer.complete(value);
  }
}

final multilinePasteConfirmationProvider =
    NotifierProvider<MultilinePasteConfirmation, MultilinePasteRequest?>(
      MultilinePasteConfirmation.new,
    );
