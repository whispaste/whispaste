/// Runs one "write" job on the Smart Mode engine (#248, ADR 0015).
///
/// The result is a draft for the preview; nothing is pasted here. A blank,
/// over-long (= cut off) or failed answer is an error and never a draft: there
/// is no raw-transcript fallback, because the instruction is not text for the
/// target app. Logs carry lengths and durations only, never content.
///
/// A fresh write may be based on a snippet (#252, ADR 0015 D10, D11): only
/// when the instruction names exactly one snippet title, the model confirms
/// it from titles and ids alone (confidence ≥ 0.90, same id), and only then
/// does the snippet text enter a prompt. Without a further instruction the
/// snippet text is the draft, without a generation call.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../recording/pipeline_step_runner.dart';
import '../smart_mode_engine.dart';
import '../smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import 'smart_write_prompt.dart';
import 'smart_write_snippet.dart';

final _log = AppLogger('SmartWrite');

/// Why no draft came out. Codes are shown via `localizeRecordingError`.
enum SmartWriteFailure {
  engineFailed,
  timedOut,
  emptyResponse,
  truncated,

  /// The user cancelled (Esc); the caller has already dropped the run.
  cancelled,

  // OpenAI write failures (#251), told apart so the user knows what to fix.
  openAiInvalidKey,
  openAiRateLimited,
  openAiTimeout,
  openAiIncomplete,
  openAiNetwork;

  String get errorCode => switch (this) {
    engineFailed => 'smart_write_failed',
    timedOut => 'smart_write_timeout',
    emptyResponse => 'smart_write_empty',
    truncated => 'smart_write_truncated',
    cancelled => smartWriteCancelledCode,
    openAiInvalidKey => 'smart_write_openai_invalid_key',
    openAiRateLimited => 'smart_write_openai_rate_limited',
    openAiTimeout => 'smart_write_openai_timeout',
    openAiIncomplete => 'smart_write_openai_incomplete',
    openAiNetwork => 'smart_write_openai_network',
  };

  /// The failure of a [SmartWriteEngineException] code; an unknown code is
  /// [engineFailed].
  static SmartWriteFailure fromEngineCode(String code) => values.firstWhere(
    (failure) => failure.errorCode == code,
    orElse: () => engineFailed,
  );
}

@immutable
class SmartWriteOutcome {
  const SmartWriteOutcome.draft(
    String this.text, {
    this.snippetTitle,
    this.snippetMissed = false,
  }) : failure = null;
  const SmartWriteOutcome.failed(SmartWriteFailure this.failure)
    : text = null,
      snippetTitle = null,
      snippetMissed = false;

  /// The trimmed draft; null on failure.
  final String? text;
  final SmartWriteFailure? failure;

  /// Title of the snippet the draft is based on (#252).
  final String? snippetTitle;

  /// The instruction named a snippet (a title candidate or a word like
  /// "snippet"), but none passed the gate: the text was written freely.
  final bool snippetMissed;
}

class SmartWriteService {
  SmartWriteService({
    required this._engine,
    this.timeout = const Duration(seconds: 60),
    this.maxOutputChars = 8000,
  });

  final SmartModeEngine _engine;

  /// The local engine call's budget; a writing run is longer than a cleanup.
  /// A [SmartWriteEngine] brings its own ([SmartWriteEngine.writeTimeout]).
  final Duration timeout;

  /// Upper bound for the local model's answer. That engine reports no "cut
  /// off" signal, so an answer above the bound counts as cut off or runaway
  /// and is dropped. A [SmartWriteEngine] reports a cut-off answer itself
  /// and has its own output limit, so the bound does not apply to it.
  final int maxOutputChars;

  /// Grace on top of [SmartWriteEngine.writeTimeout], so the engine's own
  /// timeout fires before the runner's.
  static const _engineTimeoutGrace = Duration(seconds: 5);

  /// Keeps job ids unique within one microsecond.
  int _jobCounter = 0;

  /// Ids of the write runs still waiting for the engine.
  final Set<String> _inFlight = {};

  /// Ids of the runs [cancel] hit, so a run cancelled during the snippet
  /// choice does not go on to generate.
  final Set<String> _cancelled = {};

  /// Esc while writing (#248): stops a running write so it does not keep the
  /// engine busy. A [SmartWriteEngine] aborts exactly these jobs in its HTTP
  /// client (#251); the local engine stops its generation. The aborted run
  /// ends as failed; the caller has already dropped it. No-op when no write
  /// runs, so another engine user is never hit.
  Future<void> cancel() async {
    if (_inFlight.isEmpty) return;
    _log.info('Writing cancelled by the user');
    _cancelled.addAll(_inFlight);
    final engine = _engine;
    if (engine is SmartWriteEngine) {
      _inFlight.toList().forEach(engine.cancelWrite);
      return;
    }
    await engine.cancel();
  }

  Future<SmartWriteOutcome> write({
    required String instruction,
    String? profile,
    String? previousDraft,
    bool useProfile = false,
    List<SnippetRef> snippets = const [],
  }) async {
    // Job id: ties the log lines of one run together and lets [cancel] abort
    // exactly this request.
    final jobId =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${_jobCounter++}';
    try {
      SnippetRef? snippet;
      var snippetMissed = false;
      if (previousDraft == null && snippets.isNotEmpty) {
        final candidate = snippetCandidate(instruction, snippets);
        if (candidate != null) {
          final choice = await _chooseSnippet(instruction, candidate, jobId);
          if (_cancelled.contains(jobId)) {
            return const SmartWriteOutcome.failed(SmartWriteFailure.cancelled);
          }
          final passed =
              snippetGate(choice, candidate) &&
              candidate.snippet.body.trim().isNotEmpty;
          _log.info('[$jobId] Snippet candidate, gate passed=$passed');
          if (passed) {
            snippet = candidate.snippet;
            if (snippetInstructionRest(instruction, candidate).isEmpty) {
              // D10: nothing to change, the snippet text is the draft.
              _log.info('[$jobId] Snippet inserted verbatim');
              return SmartWriteOutcome.draft(
                snippet.body.trim(),
                snippetTitle: snippet.title,
              );
            }
          }
        }
        snippetMissed =
            snippet == null && namesASnippet(instruction, candidate);
      }
      final outcome = await _generate(
        jobId: jobId,
        prompt: buildSmartWritePrompt(
          instruction: instruction,
          previousDraft: previousDraft,
          profile: profile,
          useProfile: useProfile,
          snippet: snippet?.body,
        ),
        instructionChars: instruction.length,
      );
      final text = outcome.text;
      return text == null
          ? outcome
          : SmartWriteOutcome.draft(
              text,
              snippetTitle: snippet?.title,
              snippetMissed: snippetMissed,
            );
    } finally {
      _cancelled.remove(jobId);
    }
  }

  /// The selection call (D11, D15): titles and ids only. A failed, timed
  /// out or unreadable answer is "no snippet".
  Future<SnippetChoice?> _chooseSnippet(
    String instruction,
    SnippetCandidate candidate,
    String jobId,
  ) async {
    final engine = _engine;
    final userText = buildSnippetChoiceUserText(instruction, candidate);
    _inFlight.add(jobId);
    final StepResult<String> step;
    try {
      step = engine is SmartWriteEngine
          ? await PipelineStepRunner(
              timeout: engine.writeTimeout + _engineTimeoutGrace,
            ).run<String>(
              'smart_write_snippet',
              () => engine.write(
                systemPrompt: snippetChoiceSystemPrompt,
                userText: userText,
                jobId: jobId,
                jsonSchema: snippetChoiceSchema,
              ),
            )
          : await PipelineStepRunner(timeout: timeout).run<String>(
              'smart_write_snippet',
              () => engine.run(
                systemPrompt: snippetChoiceSystemPrompt,
                userText: userText,
              ),
            );
    } finally {
      _inFlight.remove(jobId);
    }
    switch (step) {
      case Ok(:final value):
        final choice = parseSnippetChoice(value);
        if (choice == null) _log.info('[$jobId] Snippet choice unreadable');
        return choice;
      case StepTimeout():
        if (engine is SmartWriteEngine) {
          engine.cancelWrite(jobId);
        } else {
          unawaited(engine.cancel());
        }
        _log.info('[$jobId] Snippet choice timed out');
        return null;
      case FailedWith(:final error):
        _log.info('[$jobId] Snippet choice failed (${error.runtimeType})');
        return null;
    }
  }

  Future<SmartWriteOutcome> _generate({
    required String jobId,
    required SmartWritePrompt prompt,
    required int instructionChars,
  }) async {
    final engine = _engine;
    final watch = Stopwatch()..start();
    _log.info(
      '[$jobId] Writing started '
      '(instructionChars=$instructionChars, '
      'promptChars=${prompt.userText.length})',
    );
    _inFlight.add(jobId);
    final StepResult<String> step;
    try {
      step = engine is SmartWriteEngine
          ? await PipelineStepRunner(
              timeout: engine.writeTimeout + _engineTimeoutGrace,
            ).run<String>(
              'smart_write',
              () => engine.write(
                systemPrompt: prompt.systemPrompt,
                userText: prompt.userText,
                jobId: jobId,
              ),
            )
          : await PipelineStepRunner(timeout: timeout).run<String>(
              'smart_write',
              () => engine.run(
                systemPrompt: prompt.systemPrompt,
                userText: prompt.userText,
              ),
            );
    } finally {
      _inFlight.remove(jobId);
    }
    final SmartWriteOutcome outcome;
    switch (step) {
      case Ok(:final value):
        final text = value.trim();
        if (text.isEmpty) {
          outcome = const SmartWriteOutcome.failed(
            SmartWriteFailure.emptyResponse,
          );
        } else if (engine is! SmartWriteEngine &&
            text.length > maxOutputChars) {
          outcome = const SmartWriteOutcome.failed(SmartWriteFailure.truncated);
        } else {
          outcome = SmartWriteOutcome.draft(text);
        }
      case StepTimeout():
        // Stop the generation we gave up on (SmartModeEngine.cancel contract).
        if (engine is SmartWriteEngine) {
          engine.cancelWrite(jobId);
          outcome = const SmartWriteOutcome.failed(
            SmartWriteFailure.openAiTimeout,
          );
        } else {
          unawaited(engine.cancel());
          outcome = const SmartWriteOutcome.failed(SmartWriteFailure.timedOut);
        }
      case FailedWith(error: final SmartWriteEngineException error):
        outcome = SmartWriteOutcome.failed(
          SmartWriteFailure.fromEngineCode(error.code),
        );
      case FailedWith(:final error):
        _log.warning('[$jobId] Engine failed (${error.runtimeType})');
        outcome = const SmartWriteOutcome.failed(
          SmartWriteFailure.engineFailed,
        );
    }
    _log.info(
      '[$jobId] Writing finished in ${watch.elapsedMilliseconds}ms '
      '(failure=${outcome.failure?.name ?? "none"}, '
      'chars=${outcome.text?.length ?? 0})',
    );
    return outcome;
  }
}

/// The write service on the configured Smart Mode engine.
final smartWriteServiceProvider = Provider<SmartWriteService>(
  (ref) => SmartWriteService(engine: ref.watch(smartModeEngineProvider)),
);
