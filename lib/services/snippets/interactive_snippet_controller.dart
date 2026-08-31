/// Drives an interactive snippet's guided multi-field recording sequence
/// (PRD `.scratch/interactive-snippets/PRD.md`).
///
/// Sits above [RecordingOrchestrator] rather than inside it (additive —
/// "der bestehende Einzel-Aufnahme-Pfad bleibt unverändert"): it calls
/// `startRecording`/`stopRecording` once per field with
/// `RecordingTarget.templateField`, collects each field's transcript, and on
/// the last field composes and pastes/saves the combined result via
/// `RecordingOrchestrator.completeInteractiveSnippet`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/recording/recording_state.dart';
import '../recording_orchestrator.dart';
import 'interactive_snippet_composer.dart';

/// Watched by the overlay to render "Feld i/N: `<name>`" and the field
/// advance button (PRD User Story 8). `null` means no interactive-snippet
/// sequence is currently running.
class InteractiveSnippetSessionState {
  const InteractiveSnippetSessionState({
    required this.fieldIndex,
    required this.fieldCount,
    required this.fieldName,
  });

  /// 0-based index of the field currently being recorded.
  final int fieldIndex;
  final int fieldCount;
  final String fieldName;
}

class InteractiveSnippetController
    extends Notifier<InteractiveSnippetSessionState?> {
  @override
  InteractiveSnippetSessionState? build() => null;

  List<SnippetField> _fields = const [];
  String _template = '';
  final List<String> _collectedTranscripts = [];
  DateTime? _startedAt;

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
    state = InteractiveSnippetSessionState(
      fieldIndex: 0,
      fieldCount: fields.length,
      fieldName: fields.first.name,
    );
    await orchestrator.startRecording(target: RecordingTarget.templateField);
  }

  /// Completes the current field's recording — the single action the
  /// hotkey, Enter key, and overlay button all trigger identically (PRD
  /// User Story 14). Ignored while idle, or while the current field's
  /// recording hasn't started yet.
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

    state = InteractiveSnippetSessionState(
      fieldIndex: nextIndex,
      fieldCount: _fields.length,
      fieldName: _fields[nextIndex].name,
    );
    await ref
        .read(recordingOrchestratorProvider.notifier)
        .startRecording(target: RecordingTarget.templateField);
  }

  /// Discards the whole sequence — no partial save, no resume (PRD User
  /// Stories 19/20). Bound to Escape.
  Future<void> cancel() async {
    if (!isActive) return;
    final phase = ref.read(recordingProvider).phase;
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        // Smart Mode v2 (ticket 02): a field recording under an active
        // Cleanup preset can still be mid-`refining` here — without this,
        // cancelling during that window would wipe the local session state
        // while the orchestrator pipeline keeps running unattended.
        phase == RecordingPhase.refining) {
      ref.read(recordingOrchestratorProvider.notifier).reset();
    }
    _reset();
  }

  Future<void> _abort() async {
    ref.read(recordingOrchestratorProvider.notifier).reset();
    _reset();
  }

  void _reset() {
    _fields = const [];
    _template = '';
    _collectedTranscripts.clear();
    _startedAt = null;
    state = null;
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
