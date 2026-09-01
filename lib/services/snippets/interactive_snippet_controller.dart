/// Drives an interactive snippet's guided multi-field recording sequence
/// (PRD `.scratch/interactive-snippets/PRD.md`).
///
/// Sits above [RecordingOrchestrator] rather than inside it (additive —
/// "der bestehende Einzel-Aufnahme-Pfad bleibt unverändert"): it calls
/// `startRecording`/`stopRecording` once per field with
/// `RecordingTarget.templateField`, collects each field's transcript, and on
/// the last field composes and pastes/saves the combined result via
/// `RecordingOrchestrator.completeInteractiveSnippet`.
///
/// ## Interview-style flow (guided-sequence UX pass, v2)
///
/// A sequence walks through three stages per the field-tested UX (the v1
/// time-based announce alone was not perceivable — see the guided-UX
/// diagnosis pass, 2026-09-01):
///
/// 1. **Briefing** ([InteractiveSnippetStage.briefing]) — published once at
///    sequence start, BEFORE any microphone opens. The overlay shows the
///    field count, the first field's name and the Enter/Escape mechanics,
///    and stays up until the user presses Enter (or the hotkey). No timer:
///    the user decides when the interview begins.
/// 2. **Announce** ([InteractiveSnippetStage.announcing]) — a short
///    pre-roll ([kInteractiveFieldAnnounceDuration]) before each field's
///    recording, naming the field about to be recorded ("Field i/N: name").
///    Only then does the microphone open.
/// 3. **Recording** ([InteractiveSnippetStage.recording]) — the field's
///    recording runs; the overlay keeps a persistent "i/N: name" indicator
///    next to the timer for the whole take.
///
/// The stages were chosen over adding new `RecordingPhase` values (the
/// once-debated architecture option): they are purely a presentation
/// concern of THIS sequence — the recording pipeline itself is idle during
/// briefing/announce, so modelling them as core recording state would leak
/// snippet-sequence UX into every `RecordingPhase` consumer. An audio cue
/// (the other debated option) was skipped as well: the persistent on-screen
/// instruction covers the "thrown into dictation" problem without adding a
/// sound the calm-UI rules (ADR 0002) would frown at.
///
/// For the whole lifetime of a sequence, bare **Enter** (advance) and
/// **Escape** (cancel) are additionally registered as system-wide keys via
/// `HotkeyService.registerInteractiveSnippetKeys` — registered once per
/// sequence rather than per field recording on purpose: fewer
/// register/unregister transitions mean fewer platform-channel race
/// windows, and a stray Enter in the announce/transcribe gaps is already a
/// no-op via [advanceField]'s phase guard. Every exit path funnels through
/// [_reset], which unregisters them again.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/recording/recording_state.dart';
import '../hotkey_service.dart';
import '../recording_orchestrator.dart';
import 'interactive_snippet_composer.dart';

/// Pre-roll shown before each field's recording starts: long enough to read
/// "Field i/N: name", short enough not to drag out a sequence (Performance
/// is a north star — this is a deliberate, small trade for not being thrown
/// into an already-running recording unprepared). Raised from the original
/// 1000 ms: field-tested against the running app, one second was over
/// before the eye had even found the pill (guided-UX diagnosis pass).
const kInteractiveFieldAnnounceDuration = Duration(milliseconds: 1500);

/// Where a running sequence currently stands (see the library doc's
/// interview-style flow).
enum InteractiveSnippetStage {
  /// Sequence started, waiting for the user's Enter before field 1 — the
  /// one-time orientation frame. No microphone, no timer.
  briefing,

  /// The short timed pre-roll before the current field's recording — the
  /// overlay names the field; the microphone is not yet open.
  announcing,

  /// The current field's recording is running (or just finished and the
  /// pipeline is transcribing it).
  recording,
}

/// Watched by the overlay to render the guided-sequence UI (PRD User
/// Story 8). `null` means no interactive-snippet sequence is currently
/// running.
class InteractiveSnippetSessionState {
  const InteractiveSnippetSessionState({
    required this.fieldIndex,
    required this.fieldCount,
    required this.fieldName,
    this.stage = InteractiveSnippetStage.recording,
  });

  /// 0-based index of the field currently being recorded.
  final int fieldIndex;
  final int fieldCount;
  final String fieldName;

  /// Which stage of the guided flow this state describes.
  final InteractiveSnippetStage stage;

  /// True during the short pre-roll BEFORE this field's recording starts —
  /// the overlay shows the announce instruction; the microphone is not
  /// yet open. False once the field is actually recording.
  bool get announcing => stage == InteractiveSnippetStage.announcing;

  /// True while the sequence waits for the user's first Enter (the
  /// orientation frame shown before field 1's announce).
  bool get briefing => stage == InteractiveSnippetStage.briefing;
}

class InteractiveSnippetController
    extends Notifier<InteractiveSnippetSessionState?> {
  @override
  InteractiveSnippetSessionState? build() {
    // A pending announce pre-roll must not touch `state` after the provider
    // is gone (app teardown mid-sequence): bumping the epoch makes the
    // post-delay check in [_announceThenRecord] bail out instead.
    ref.onDispose(() => _epoch++);
    return null;
  }

  List<SnippetField> _fields = const [];
  String _template = '';
  final List<String> _collectedTranscripts = [];
  DateTime? _startedAt;

  /// Monotonic sequence epoch, bumped by [_reset]: an announce pre-roll that
  /// wakes up after its sequence was cancelled (or replaced) sees a changed
  /// epoch and must not start a recording.
  int _epoch = 0;

  /// Announce pre-roll length — overridable so tests can shrink it to zero
  /// instead of sleeping through real wall-clock time.
  @visibleForTesting
  Duration announceDuration = kInteractiveFieldAnnounceDuration;

  /// The awaitable the announce pre-roll waits on — overridable so tests can
  /// hold the pre-roll open deterministically (e.g. via a `Completer`).
  @visibleForTesting
  Future<void> Function(Duration) announceDelay = (d) =>
      Future<void>.delayed(d);

  bool get isActive => state != null;

  /// Starts a new sequence for [fields] (already sorted by `sortOrder`),
  /// composing the result into [template] (the parent snippet's `body`,
  /// holding `{{fieldName}}` placeholders) once every field is recorded.
  /// No-op if a sequence is already active (Out of Scope: nesting) or
  /// [fields] is empty -- a single field is legitimate (PRD User Story 4,
  /// relaxed from a minimum of two in a8445010).
  Future<void> start(
    List<SnippetField> fields, {
    required String template,
  }) async {
    if (isActive || fields.isEmpty) return;

    _fields = fields;
    _template = template;
    _collectedTranscripts.clear();
    _startedAt = DateTime.now();

    final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    await orchestrator.primeForInteractiveSnippet();
    // Register the session keys BEFORE the first session state is published:
    // every exit path runs [_reset] only while a session is active
    // (`isActive` guards), so the unregister there can never race ahead of a
    // still-pending registration.
    await ref
        .read(hotkeyServiceProvider.notifier)
        .registerInteractiveSnippetKeys(
          onAdvance: () => unawaited(advanceField()),
          onCancel: () => unawaited(cancel()),
        );
    // Orientation first, microphone later: the briefing frame stays up until
    // the user presses Enter (see [advanceField]) — being dropped straight
    // into field 1's countdown was the "unexplained hotkey presses" feel the
    // guided-UX pass exists to remove.
    state = InteractiveSnippetSessionState(
      fieldIndex: 0,
      fieldCount: _fields.length,
      fieldName: _fields[0].name,
      stage: InteractiveSnippetStage.briefing,
    );
  }

  /// Advances the guided flow — the single action the hotkey, Enter key,
  /// and overlay button all trigger identically (PRD User Story 14).
  ///
  /// - During the briefing frame it starts field 1's announce pre-roll.
  /// - During a field's recording it completes that field.
  /// - After a field's recording auto-stopped on its own (max-duration or
  ///   silence guard — the pipeline lands in `done` without this controller
  ///   ever seeing a stop), it collects that field's transcript and moves
  ///   on. Without this branch the `recording`-phase guard below turned
  ///   Enter into a dead key after any auto-stop and stranded the whole
  ///   sequence (observed live, 2026-09-01: max-duration fired mid-field,
  ///   session stayed active, every hotkey no-op'd until app restart).
  /// - Ignored while idle or during an announce pre-roll.
  Future<void> advanceField() async {
    if (!isActive) return;

    if (state!.stage == InteractiveSnippetStage.briefing) {
      await _announceThenRecord(0);
      return;
    }
    if (state!.stage != InteractiveSnippetStage.recording) return;

    final phase = ref.read(recordingProvider).phase;
    if (phase == RecordingPhase.recording) {
      await ref.read(recordingOrchestratorProvider.notifier).stopRecording();
    } else if (phase == RecordingPhase.error) {
      // The pipeline failed on its own (e.g. empty-transcript error after an
      // auto-stop) — same stranding hazard as the done case: without this,
      // Enter would be dead and the session stuck. Tear the sequence down.
      await _abort();
      return;
    } else if (phase != RecordingPhase.done) {
      // Transcribing/refining is still in flight (Enter pressed twice), or
      // the pipeline is idle without a take to collect — nothing to
      // advance past yet.
      return;
    }

    final result = ref.read(recordingProvider);
    if (result.phase == RecordingPhase.error) {
      await _abort();
      return;
    }

    _collectedTranscripts.add(result.transcript ?? '');
    final nextIndex = state!.fieldIndex + 1;
    if (nextIndex >= _fields.length) {
      await _finish();
      return;
    }

    await _announceThenRecord(nextIndex);
  }

  /// Publishes the announce pre-roll for the field at [index], waits
  /// [announceDuration], then opens the microphone — unless the sequence
  /// was cancelled (or replaced) while the pre-roll was pending.
  Future<void> _announceThenRecord(int index) async {
    final epoch = _epoch;
    state = InteractiveSnippetSessionState(
      fieldIndex: index,
      fieldCount: _fields.length,
      fieldName: _fields[index].name,
      stage: InteractiveSnippetStage.announcing,
    );
    await announceDelay(announceDuration);
    if (_epoch != epoch) return; // Cancelled during the pre-roll.

    state = InteractiveSnippetSessionState(
      fieldIndex: index,
      fieldCount: _fields.length,
      fieldName: _fields[index].name,
      stage: InteractiveSnippetStage.recording,
    );
    await ref
        .read(recordingOrchestratorProvider.notifier)
        .startRecording(target: RecordingTarget.templateField);
  }

  /// Discards the whole sequence — no partial save, no resume (PRD User
  /// Stories 19/20). Bound to Escape (session-scoped, see the library doc),
  /// the overlay close button, and the overlay context menu.
  Future<void> cancel() async {
    if (!isActive) return;
    final phase = ref.read(recordingProvider).phase;
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        // Smart Mode v2 (ticket 02): a field recording under an active
        // Cleanup preset can still be mid-`refining` here — without this,
        // cancelling during that window would wipe the local session state
        // while the orchestrator pipeline keeps running unattended.
        phase == RecordingPhase.refining ||
        // A cancel during a between-fields announce pre-roll lands here
        // with the PREVIOUS field's `done` still published — reset it too,
        // so the overlay's phase listener hides the pill instead of leaving
        // a stale done/announce frame behind.
        phase == RecordingPhase.done) {
      ref.read(recordingOrchestratorProvider.notifier).reset();
    }
    _reset();
  }

  Future<void> _abort() async {
    ref.read(recordingOrchestratorProvider.notifier).reset();
    _reset();
  }

  void _reset() {
    _epoch++;
    _fields = const [];
    _template = '';
    _collectedTranscripts.clear();
    _startedAt = null;
    state = null;
    // Drop the session-scoped Enter/Escape grabs on EVERY exit path (finish,
    // cancel, abort) — fire-and-forget: nothing below depends on the
    // platform round trip, and HotkeyService's epoch guard covers a re-start
    // racing this unregister.
    unawaited(
      ref
          .read(hotkeyServiceProvider.notifier)
          .unregisterInteractiveSnippetKeys(),
    );
  }

  Future<void> _finish() async {
    final fieldNames = [for (final f in _fields) f.name];
    final composed = composeInteractiveSnippetText(
      template: _template,
      fieldNames: fieldNames,
      fieldTranscripts: _collectedTranscripts,
    );
    final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    _reset();
    await ref
        .read(recordingOrchestratorProvider.notifier)
        .completeInteractiveSnippet(
          composedText: composed,
          audioDuration: elapsed,
        );
  }
}

final interactiveSnippetControllerProvider =
    NotifierProvider<
      InteractiveSnippetController,
      InteractiveSnippetSessionState?
    >(InteractiveSnippetController.new);
