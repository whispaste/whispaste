/// Learning from edits made in the target app after a paste (issue #384).
///
/// After a confirmed paste, [TargetFieldWatch] re-reads only the section of
/// the focused field around the caret, bounded by the pasted length plus
/// slack on both sides (see `target_field_span.dart`), a few times within
/// [TargetFieldWatch.window]. The pasted words are anchored by their content,
/// not by the caret, so the user may click anywhere inside them. The watch
/// stops when the pasted text is no longer recognisable (cleared field, caret
/// or focus moved away) and compares the last snapshot that still held it
/// with what was pasted: each changed place becomes its own
/// [CorrectionSignal] with [CorrectionSignalSource.targetAppEdit] and a few
/// words of context in front. The usual candidate rules (1 to 4 changed
/// words, stopwords, threshold) decide the rest.
///
/// Privacy: read spans stay in memory, are never logged and never leave the
/// device. Password fields are refused natively. Nothing here runs on the
/// hotkey or paste path: the watch starts after the paste returned and every
/// native read has its own deadline.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/build_config.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/polled_channel_call.dart';
import '../paste/desktop_paster.dart' show pasterProvider;
import '../paste/dictation_start_probe.dart';
import 'correction_learning_service.dart';
import 'correction_signal.dart';
import 'target_field_span.dart';

final _log = AppLogger('TargetFieldLearning');

/// Reads the bounded section around the caret of the focused field.
abstract interface class TargetFieldReader {
  Future<TargetFieldRead> readInsertedSpan(String expectedText);
}

/// Channel client, same contract on macOS, Windows and Linux.
///
/// `readInsertedSpan({expectedText, slackChars, afterChars})` answers
/// `{readable, text, matchesExpected, reason, pattern}`:
/// - `text`: the section from the length of `expectedText` plus `slackChars`
///   before the caret to `afterChars` after it (clamped to the field);
///   `null` when not readable. Never the whole document, never logged.
/// - `matchesExpected`: `text` (without CR) contains `expectedText`.
/// - `reason`: `ok`, `no_focus`, `own_window`, `password_field`,
///   `no_text_pattern`, `no_caret`, `busy`, `uia_unavailable`, `uia_error`
///   (Windows), `permission_missing`, `sandbox` (macOS, Linux) or
///   `unsupported`; grouped by [TargetFieldUnreadableReason.fromCode].
/// - `pattern`: which accessibility path answered, for diagnosis only.
///
/// A field without a caret (Warp's input editor on macOS) answers a section
/// of its value in the same total bound: around the last unchanged copy of
/// the pasted text, else its end.
class ChannelTargetFieldReader implements TargetFieldReader, CaretTextReader {
  ChannelTargetFieldReader({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.whispaste.inserted_span');

  final MethodChannel _channel;

  /// Accessibility reads are fast (Windows measured 64 to 114 ms including
  /// the paste); a slower answer means a busy target app and counts as error.
  static const Duration readTimeout = Duration(seconds: 1);

  final _call = PolledChannelCall<Object?>(timeout: readTimeout);

  @override
  Future<TargetFieldRead> readInsertedSpan(String expectedText) => _read({
    'expectedText': expectedText,
    'slackChars': targetFieldSpanSlack,
    'afterChars': expectedText.length + targetFieldSpanSlack,
  });

  @override
  Future<TargetFieldRead> readBeforeCaret(int chars) =>
      _read({'expectedText': '', 'slackChars': chars, 'afterChars': 0});

  Future<TargetFieldRead> _read(Map<String, Object> arguments) async {
    try {
      final result = await _call.run(
        () => _channel.invokeMethod<Object?>('readInsertedSpan', arguments),
      );
      if (result.status != PolledCallStatus.answered) {
        return const TargetFieldRead.unreadable(
          TargetFieldUnreadableReason.error,
        );
      }
      return TargetFieldRead.fromReply(result.value);
    } on MissingPluginException {
      return const TargetFieldRead.unreadable(
        TargetFieldUnreadableReason.unsupported,
      );
    } on Object catch (e) {
      // The error text never carries field contents; log only its type.
      _log.debug('Target field read failed (${e.runtimeType})');
      return const TargetFieldRead.unreadable(
        TargetFieldUnreadableReason.error,
      );
    }
  }
}

/// Last read status per target app, for the learning log (#383): "WhisPaste
/// can follow edits here" or why not.
class TargetFieldAppStatus {
  const TargetFieldAppStatus({
    required this.app,
    this.reason,
    this.learned = false,
  });

  /// Target app of the paste (bundle id, executable or app name), or an
  /// empty string if unknown.
  final String app;

  /// Null when the field was readable.
  final TargetFieldUnreadableReason? reason;

  /// Whether this watch found at least one changed place.
  final bool learned;

  bool get readable => reason == null;
}

class TargetFieldStatusNotifier
    extends Notifier<Map<String, TargetFieldAppStatus>> {
  @override
  Map<String, TargetFieldAppStatus> build() => const {};

  /// Keeps the newest status last, so the log can tell the latest read.
  void record(TargetFieldAppStatus status) {
    state = {
      for (final e in state.entries)
        if (e.key != status.app) e.key: e.value,
      status.app: status,
    };
  }
}

/// Reasons that hold for every target app, shown once instead of per app.
const _globalTargetFieldReasons = {
  TargetFieldUnreadableReason.sandbox,
  TargetFieldUnreadableReason.permission,
  TargetFieldUnreadableReason.unsupported,
};

/// What the learning log shows about target apps, newest first. If the latest
/// read failed for a reason that holds for every app (Mac App Store sandbox,
/// missing permission, no runner), only that one status with an empty app is
/// shown. Transient `busy` reads are left out. In the Mac App Store build the
/// Dictionary already says once that other apps cannot be read there
/// ([masCorrectionHintVisible]), so the sandbox status is not repeated.
List<TargetFieldAppStatus> targetFieldStatusForLog(
  Map<String, TargetFieldAppStatus> byApp, {
  bool isMasBuild = kIsMasBuild,
}) {
  if (byApp.isEmpty) return const [];
  final latest = byApp.values.last;
  if (isMasBuild && latest.reason == TargetFieldUnreadableReason.sandbox) {
    return const [];
  }
  if (_globalTargetFieldReasons.contains(latest.reason)) {
    return [TargetFieldAppStatus(app: '', reason: latest.reason)];
  }
  return [
    for (final s in byApp.values.toList().reversed)
      if (s.reason != TargetFieldUnreadableReason.busy &&
          !_globalTargetFieldReasons.contains(s.reason))
        s,
  ];
}

/// Whether the Dictionary shows the calm hint that corrections made in other
/// apps cannot be read (#934). Only the Mac App Store build: its sandbox
/// forbids reading other apps' fields, so the target-field watch never learns.
bool masCorrectionHintVisible({bool isMasBuild = kIsMasBuild}) => isMasBuild;

/// In-memory only; cleared with the app.
final targetFieldStatusProvider =
    NotifierProvider<
      TargetFieldStatusNotifier,
      Map<String, TargetFieldAppStatus>
    >(TargetFieldStatusNotifier.new);

/// Follows one paste. Timing is injectable so tests run on simulated time.
class TargetFieldWatch {
  TargetFieldWatch({
    required this.reader,
    DateTime Function()? now,
    this.firstDelay = const Duration(milliseconds: 800),
    this.interval = const Duration(seconds: 3),
    this.window = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final TargetFieldReader reader;
  final DateTime Function() _now;

  /// First read after the paste returned (the text is already there on all
  /// measured apps; the delay lets the target app settle).
  final Duration firstDelay;

  /// Pause between snapshots.
  final Duration interval;

  /// Longest time a paste is followed.
  final Duration window;

  /// A new paste starts a new watch; the older one stops before its next
  /// read and keeps its last snapshot.
  int _generation = 0;

  /// Follows the paste of [inserted] and returns the outcome. Never throws.
  Future<TargetFieldWatchResult> follow(String inserted) async {
    final generation = ++_generation;
    if (inserted.trim().isEmpty ||
        inserted.length > targetFieldMaxInsertedChars) {
      return const TargetFieldWatchResult.skipped();
    }
    final started = _now();
    List<TargetEditPair>? lastPairs;
    TargetFieldUnreadableReason? firstFailure;
    var delay = firstDelay;
    while (true) {
      await Future<void>.delayed(delay);
      delay = interval;
      if (generation != _generation) break;
      final read = await reader.readInsertedSpan(inserted);
      final expired = _now().difference(started) >= window;
      if (!read.readable) {
        // Another read still running: try again on the next tick.
        if (read.reason == TargetFieldUnreadableReason.busy && !expired) {
          continue;
        }
        // Unreadable on the first look: the honest status for this app.
        // Later (user left the field, app busy): keep the last snapshot.
        if (lastPairs == null) firstFailure = read.reason;
        break;
      }
      final pairs = read.matchesExpected
          ? const <TargetEditPair>[]
          : targetEditPairs(inserted, read.text!);
      if (pairs == null) break;
      lastPairs = pairs;
      if (expired) break;
    }

    if (firstFailure != null) {
      return TargetFieldWatchResult.unreadable(firstFailure);
    }
    // Readable; no pairs when nothing changed or the pasted words were never
    // found (caret moved away before the first look).
    final at = _now();
    return TargetFieldWatchResult.readable(
      signals: [
        for (final pair in lastPairs ?? const <TargetEditPair>[])
          CorrectionSignal(
            sourceText: pair.sourceText,
            targetText: pair.targetText,
            contextBefore: pair.contextBefore,
            timestamp: at,
            source: CorrectionSignalSource.targetAppEdit,
          ),
      ],
    );
  }
}

class TargetFieldWatchResult {
  const TargetFieldWatchResult.skipped()
    : skipped = true,
      reason = null,
      signals = const [];

  const TargetFieldWatchResult.readable({this.signals = const []})
    : skipped = false,
      reason = null;

  const TargetFieldWatchResult.unreadable(
    TargetFieldUnreadableReason this.reason,
  ) : skipped = false,
      signals = const [];

  final bool skipped;
  final TargetFieldUnreadableReason? reason;

  /// One before/after pair per changed place, with context in front. The
  /// candidate rules decide whether each is a correction.
  final List<CorrectionSignal> signals;
}

final caretTextReaderProvider = Provider<CaretTextReader>(
  (ref) => ChannelTargetFieldReader(),
);

final targetFieldReaderProvider = Provider<TargetFieldReader>(
  (ref) => ChannelTargetFieldReader(),
);

final targetFieldWatchProvider = Provider<TargetFieldWatch>(
  (ref) => TargetFieldWatch(reader: ref.watch(targetFieldReaderProvider)),
);

/// Starts following a confirmed paste of [transcript], if "Aus Korrekturen
/// lernen" is on. Fire-and-forget: the caller does not await it, and every
/// failure ends quietly with a status for the learning log.
Future<void> followTargetFieldAfterPaste(Ref ref, String transcript) async {
  final enabled =
      ref.read(settingsProvider).value?.behavior.correctionLearningEnabled ??
      true;
  if (!enabled) return;
  try {
    final app = await _pasteTargetApp(ref);
    final result = await ref.read(targetFieldWatchProvider).follow(transcript);
    if (result.skipped) {
      _log.info(targetFieldWatchLogLine(app: app, skipped: true));
      return;
    }
    final signals = result.signals;
    ref
        .read(targetFieldStatusProvider.notifier)
        .record(
          TargetFieldAppStatus(
            app: app ?? '',
            reason: result.reason,
            learned: signals.isNotEmpty,
          ),
        );
    _log.info(
      targetFieldWatchLogLine(
        app: app,
        reason: result.reason,
        changes: signals.length,
      ),
    );
    if (signals.isEmpty) return;
    // The switch may have been turned off while the watch ran.
    final stillEnabled =
        ref.read(settingsProvider).value?.behavior.correctionLearningEnabled ??
        true;
    if (!stillEnabled) return;
    final service = ref.read(correctionLearningServiceProvider);
    final db = ref.read(historyDatabaseProvider);
    for (final signal in signals) {
      await service.recordSignal(signal, db);
    }
  } on Object catch (e) {
    _log.info('Target field watch: ended early (${e.runtimeType})');
  }
}

/// The one info line per target-field watch (#934): app, reason (or
/// `readable`, or `skipped` for empty or overlong pastes) and the number of
/// changed places. Never contains field or pasted text. A full path as app is
/// cut to its last segment, so no user folder names reach the log.
String targetFieldWatchLogLine({
  required String? app,
  TargetFieldUnreadableReason? reason,
  int changes = 0,
  bool skipped = false,
}) {
  final raw = (app ?? '').trim();
  final name = raw.isEmpty ? 'unknown' : raw.split(RegExp(r'[/\\]')).last;
  final status = skipped ? 'skipped' : (reason?.name ?? 'readable');
  return 'Target field watch: app=$name, reason=$status, changes=$changes';
}

/// The app the paste went to, as captured at hotkey time. Bounded like the
/// history save's lookup; failures leave it unknown.
Future<String?> _pasteTargetApp(Ref ref) async {
  try {
    return await ref
        .read(pasterProvider)
        ?.getTargetBundleId()
        .timeout(const Duration(seconds: 1));
  } on Object {
    return null;
  }
}
