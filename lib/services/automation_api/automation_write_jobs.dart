/// Write jobs started over the local automation API (#255, ADR 0015 D22).
///
/// A job takes a written instruction instead of a transcript, runs it on the
/// same write path as the Smart Mode hotkey and pastes the result straight
/// into the foreground app: there is no preview and no Enter step. In place
/// of the preview it is guarded by:
///   - the write scope (separate token, off by default; see the middleware),
///   - at most [kAutomationWriteRateLimit] starts per minute and one open
///     job at a time,
///   - the target check: the app in front when the request came in must
///     still be in front when the text is pasted (except Wayland, D18),
///   - instant revocation: the switch off or a new write token stops every
///     open job before it pastes,
///   - a protocol of the last [kAutomationWriteProtocolSize] jobs, in memory
///     only and without instruction or result text.
///
/// This file holds the policy only. The native and engine work lives behind
/// [AutomationWriteRunner], which `main.dart` wires to the Smart Mode write
/// path, so this file stays free of the recording/engine imports (same seam
/// as the dictation trigger, see `automation_api_controller.dart`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';

final _log = AppLogger('AutomationWrite');

/// Starts allowed per sliding minute.
const kAutomationWriteRateLimit = 10;

/// Entries the in-memory protocol keeps.
const kAutomationWriteProtocolSize = 20;

/// Longest instruction the write route accepts, in characters.
const kAutomationWriteMaxInstructionChars = 4000;

enum AutomationWriteStatus { running, inserted, failed }

/// Context sources a request may switch off for its own job. A request can
/// only narrow what the settings allow, never widen it (ADR 0015 D14/D20).
@immutable
class AutomationWriteContextLimits {
  const AutomationWriteContextLimits({
    this.profile = true,
    this.app = true,
    this.clipboard = true,
  });

  final bool profile;
  final bool app;
  final bool clipboard;
}

/// One protocol line. Never holds instruction or result text (D22).
@immutable
class AutomationWriteRecord {
  const AutomationWriteRecord({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.instructionChars,
    this.errorCode,
    this.resultChars,
    this.duration,
    this.targetChecked = true,
  });

  final String id;
  final DateTime startedAt;
  final AutomationWriteStatus status;
  final int instructionChars;

  /// Why nothing was pasted; null while running and after a paste.
  final String? errorCode;

  /// Length of the pasted text; null until a result exists.
  final int? resultChars;
  final Duration? duration;

  /// False on Wayland, where the target app cannot be checked (D18).
  final bool targetChecked;

  AutomationWriteRecord finish({
    required AutomationWriteStatus status,
    required Duration duration,
    String? errorCode,
    int? resultChars,
    bool? targetChecked,
  }) => AutomationWriteRecord(
    id: id,
    startedAt: startedAt,
    status: status,
    instructionChars: instructionChars,
    errorCode: errorCode,
    resultChars: resultChars ?? this.resultChars,
    duration: duration,
    targetChecked: targetChecked ?? this.targetChecked,
  );

  /// The wire shape of `GET /v1/write/status` and the `POST /v1/write`
  /// answer: status and sizes, never text.
  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.name,
    'error': ?errorCode,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_ms': ?duration?.inMilliseconds,
    'instruction_chars': instructionChars,
    'result_chars': ?resultChars,
    'target_checked': targetChecked,
  };
}

/// The app a job will paste into, captured when the request came in.
@immutable
class AutomationWriteTarget {
  const AutomationWriteTarget({this.id, this.wayland = false});

  /// Foreground app id (same vocabulary as the paste target); null when it
  /// could not be read or is a WhisPaste window.
  final String? id;

  /// Wayland gives no checkable target; pasting goes ahead (D18).
  final bool wayland;
}

/// Result of [AutomationWriteRunner.write]: a text or an error code.
@immutable
class AutomationWriteDraft {
  const AutomationWriteDraft.text(String this.text) : errorCode = null;
  const AutomationWriteDraft.failed(String this.errorCode) : text = null;

  final String? text;
  final String? errorCode;
}

/// Native and engine work of one job, supplied by `main.dart`.
abstract interface class AutomationWriteRunner {
  /// Reads the foreground app at request time.
  Future<AutomationWriteTarget> captureTarget();

  /// Error code when the write engine cannot run now, else null.
  Future<String?> preflight();

  Future<AutomationWriteDraft> write(
    String instruction,
    AutomationWriteContextLimits limits,
  );

  /// Pastes [text] when [target] is still in front. Returns null after a
  /// successful paste, else an error code; nothing is copied on failure,
  /// because no one may be looking at the screen.
  /// [stillAllowed] is asked right before the paste, so a revocation
  /// during the target check still wins.
  Future<String?> insert(
    String text,
    AutomationWriteTarget target, {
    required bool Function() stillAllowed,
  });
}

/// Default runner: fails loudly when `main.dart` did not wire the real one.
final automationWriteRunnerProvider = Provider<AutomationWriteRunner>(
  (ref) => throw StateError(
    'automationWriteRunnerProvider was never configured — override it at '
    'app startup.',
  ),
);

sealed class AutomationWriteStart {
  const AutomationWriteStart();
}

class AutomationWriteStarted extends AutomationWriteStart {
  const AutomationWriteStarted(this.record, this.done);

  final AutomationWriteRecord record;

  /// Completes with the final record.
  final Future<AutomationWriteRecord> done;
}

class AutomationWriteRateLimited extends AutomationWriteStart {
  const AutomationWriteRateLimited(this.retryAfter);

  final Duration retryAfter;
}

class AutomationWriteBusy extends AutomationWriteStart {
  const AutomationWriteBusy(this.openId);

  final String openId;
}

/// The protocol (newest first) plus the job policy.
class AutomationWriteJobs extends Notifier<List<AutomationWriteRecord>> {
  AutomationWriteJobs({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<DateTime> _starts = [];
  String? _openId;
  int _generation = 0;
  int _counter = 0;

  @override
  List<AutomationWriteRecord> build() => const [];

  AutomationWriteRecord? lookup(String id) {
    for (final record in state) {
      if (record.id == id) return record;
    }
    return null;
  }

  /// Stops every open job before it pastes (switch off, new write token).
  /// The job ends as `failed` with `revoked`.
  void revokeAll() {
    _generation++;
    if (_openId != null) _log.info('[$_openId] Write job revoked');
  }

  AutomationWriteStart start(
    String instruction, {
    AutomationWriteContextLimits limits = const AutomationWriteContextLimits(),
  }) {
    final now = _clock();
    final open = _openId;
    if (open != null) return AutomationWriteBusy(open);
    _starts.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_starts.length >= kAutomationWriteRateLimit) {
      final retry = const Duration(minutes: 1) - now.difference(_starts.first);
      return AutomationWriteRateLimited(retry);
    }
    _starts.add(now);
    final id = 'w${now.microsecondsSinceEpoch.toRadixString(36)}${++_counter}';
    final record = AutomationWriteRecord(
      id: id,
      startedAt: now,
      status: AutomationWriteStatus.running,
      instructionChars: instruction.length,
    );
    _openId = id;
    _put(record);
    final done = _run(record, instruction, limits, _generation);
    return AutomationWriteStarted(record, done);
  }

  Future<AutomationWriteRecord> _run(
    AutomationWriteRecord record,
    String instruction,
    AutomationWriteContextLimits limits,
    int generation,
  ) async {
    final watch = Stopwatch()..start();
    // Lengths only: the instruction never reaches the log.
    _log.info(
      '[${record.id}] Write job started '
      '(instructionChars=${record.instructionChars})',
    );
    AutomationWriteRecord finish(
      AutomationWriteStatus status, {
      String? errorCode,
      int? resultChars,
      bool? targetChecked,
    }) {
      final done = record.finish(
        status: status,
        duration: watch.elapsed,
        errorCode: errorCode,
        resultChars: resultChars,
        targetChecked: targetChecked,
      );
      _openId = null;
      _put(done);
      _log.info(
        '[${record.id}] Write job ${status.name} in '
        '${watch.elapsedMilliseconds}ms '
        '(error=${errorCode ?? "none"}, resultChars=${resultChars ?? 0})',
      );
      return done;
    }

    bool revoked() => generation != _generation;

    try {
      final runner = ref.read(automationWriteRunnerProvider);
      final target = await runner.captureTarget();
      if (!target.wayland && target.id == null) {
        return finish(
          AutomationWriteStatus.failed,
          errorCode: 'automation_write_target_unknown',
        );
      }
      final blocked = await runner.preflight();
      if (blocked != null) {
        return finish(AutomationWriteStatus.failed, errorCode: blocked);
      }
      if (revoked()) {
        return finish(AutomationWriteStatus.failed, errorCode: 'revoked');
      }
      final draft = await runner.write(instruction, limits);
      final text = draft.text;
      if (text == null) {
        return finish(
          AutomationWriteStatus.failed,
          errorCode: draft.errorCode ?? 'smart_write_failed',
        );
      }
      if (revoked()) {
        return finish(
          AutomationWriteStatus.failed,
          errorCode: 'revoked',
          resultChars: text.length,
        );
      }
      final failure = await runner.insert(
        text,
        target,
        stillAllowed: () => !revoked(),
      );
      return finish(
        failure == null
            ? AutomationWriteStatus.inserted
            : AutomationWriteStatus.failed,
        errorCode: failure,
        resultChars: text.length,
        targetChecked: !target.wayland,
      );
    } on Object catch (e) {
      _log.warning('[${record.id}] Write job threw (${e.runtimeType})');
      return finish(
        AutomationWriteStatus.failed,
        errorCode: 'smart_write_failed',
      );
    }
  }

  void _put(AutomationWriteRecord record) {
    // A job can outlive the notifier (app shutdown); its end is then moot.
    if (!ref.mounted) return;
    final next = [
      record,
      for (final r in state)
        if (r.id != record.id) r,
    ];
    state = next.length > kAutomationWriteProtocolSize
        ? next.sublist(0, kAutomationWriteProtocolSize)
        : next;
  }

  @visibleForTesting
  int get generation => _generation;
}

final automationWriteJobsProvider =
    NotifierProvider<AutomationWriteJobs, List<AutomationWriteRecord>>(
      AutomationWriteJobs.new,
    );
