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
/// ## Interview-style flow (guided-sequence UX pass)
///
/// Every field is preceded by a short ANNOUNCE pre-roll
/// ([kInteractiveFieldAnnounceDuration]): the session state is published
/// with [InteractiveSnippetSessionState.announcing] set, the floating
/// overlay shows "Field i/N: name – get ready…", and only then does the
/// microphone open. This was chosen over adding a new `RecordingPhase`
/// value (the once-debated architecture option): the pre-roll is purely a
/// presentation concern of THIS sequence — the recording pipeline itself is
/// idle during it, so modelling it as core recording state would leak
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
/// "Field i/N: name – get ready…", short enough not to drag out a sequence
/// (Performance is a north star — this is a deliberate, small trade for not
/// being thrown into an already-running recording unprepared).
const kInteractiveFieldAnnounceDuration = Duration(milliseconds: 1000);

/// Watched by the overlay to render the guided-sequence UI (PRD User
/// Story 8). `null` means no interactive-snippet sequence is currently
/// running.
class InteractiveSnippetSessionState {
  const InteractiveSnippetSessionState({
    required this.fieldIndex,
    required this.fieldCount,
    required this.fieldName,
    this.announcing = false,
  });

  /// 0-based index of the field currently being recorded.
  final int fieldIndex;
  final int fieldCount;
  final String fieldName;

  /// True during the short pre-roll BEFORE this field's recording starts —
  /// the overlay shows the "get ready" instruction; the microphone is not
  /// yet open. False once the field is actually recording.
  final bool announcing;
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
    await _announceThenRecord(0);
  }

  /// Completes the current field's recording — the single action the
  /// hotkey, Enter key, and overlay button all trigger identically (PRD
  /// User Story 14). Ignored while idle, during a field's announce
  /// pre-roll, or while the current field's recording hasn't started yet.
  Future<void> advanceField() async {
    if (!isActive) return;
    if (ref.read(recordingProvider).phase != RecordingPhase.recording) return;

    await ref.read(recordingOrchestratorProvider.notifier).stopRecording();

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
      announcing: true,
    );
    await announceDelay(announceDuration);
    if (_epoch != epoch) return; // Cancelled during the pre-roll.

    state = InteractiveSnippetSessionState(
      fieldIndex: index,
      fieldCount: _fields.length,
      fieldName: _fields[index].name,
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
