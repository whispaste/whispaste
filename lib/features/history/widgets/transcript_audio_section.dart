/// Transcript and audio side by side (#672): when a recording keeps its audio,
/// each sentence of the transcript leads to its place in the recording and
/// the sentence playing now is marked.
///
/// The time marks are estimated from the kept WAV (where speech sounds and
/// where it pauses) against the text the audio was transcribed into, so every
/// recording whose audio still exists gets them, whatever engine wrote it.
/// Edited sentences keep their mark when they still resemble a sentence of
/// that text; the rest is shown without a mark and counted, never guessed.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/data/database.dart';
import '../../../core/data/entry_version_rules.dart';
import '../../../core/data/note_version_limits.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio/encryption/recording_vault.dart';
import '../../../services/audio/playback/recording_playback.dart';
import '../../../services/audio/transcript_timing.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_icon_button.dart';

/// The kept audio of a recording, analysed for speech, with the text it was
/// transcribed into.
class TranscriptAudio {
  const TranscriptAudio({
    required this.path,
    required this.activity,
    required this.basis,
  });

  final String path;
  final SpeechActivity activity;

  /// The text the audio became first: the original transcript, else the
  /// oldest dictated version, else the current text.
  final String basis;

  /// Time marks for the [current] text of the recording.
  TranscriptTiming timingFor(String current) =>
      timeTranscript(current: current, basis: basis, activity: activity);
}

/// The text the audio of [entry] was transcribed into, see
/// [TranscriptAudio.basis].
Future<String> transcriptAudioBasis(
  HistoryDatabase db,
  HistoryEntry entry,
) async {
  final original = entry.originalTranscript;
  if (original != null && original.trim().isNotEmpty) return original;
  final versions = await db.entryVersionsFor(entry.id);
  for (final v in versions.reversed) {
    if (EntryVersionSource.fromName(v.source) == EntryVersionSource.dictated) {
      return decodeNoteVersionBody(v.content);
    }
  }
  return entry.content;
}

/// The kept audio of an entry, or null when it has none on disk (or it
/// cannot be read). The analysis runs off the UI thread.
final transcriptAudioProvider = FutureProvider.autoDispose
    .family<TranscriptAudio?, String>((ref, entryId) async {
      final db = ref.read(historyDatabaseProvider);
      final attachment = await db.latestAudioAttachment(entryId);
      if (attachment == null) return null;
      final path = attachment.filepath;
      if (!await File(path).exists()) return null;
      final entry = await db.getEntry(entryId);
      if (entry == null) return null;
      try {
        final bytes = await ref.read(recordingVaultProvider).read(path);
        final activity = await Isolate.run(() => analyzeSpeechActivity(bytes));
        if (activity.frames.isEmpty) return null;
        return TranscriptAudio(
          path: path,
          activity: activity,
          basis: await transcriptAudioBasis(db, entry),
        );
      } on Object {
        return null;
      }
    });

/// `m:ss` (or `h:mm:ss`) of [d] for a time mark.
String formatTimeMark(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$sec';
  return '$m:$sec';
}

/// Plays [entryId] from the sentence of [text] at [offset] (the caret).
/// Announces when the recording has no audio or the sentence no mark.
Future<void> playTranscriptSentenceAt(
  BuildContext context,
  WidgetRef ref, {
  required String entryId,
  required String text,
  required int offset,
}) async {
  final l10n = L10n.of(context);
  final view = View.of(context);
  final direction = Directionality.of(context);
  final audio = await ref.read(transcriptAudioProvider(entryId).future);
  if (audio == null) {
    announce(view, l10n.historyAudioNoAudio, direction);
    return;
  }
  final timing = audio.timingFor(text);
  final index = sentenceIndexAt([
    for (final s in timing.sentences) s.sentence,
  ], offset);
  final start = index == null ? null : timing.sentences[index].start;
  if (start == null) {
    announce(view, l10n.historyAudioSentenceUnmatched, direction);
    return;
  }
  await ref
      .read(recordingPlaybackProvider.notifier)
      .playFrom(entryId, audio.path, start);
}

/// The disclosure below the transcript: play/stop for the whole recording
/// and, opened, the sentences with their time marks. Shown only when the
/// entry still has its audio.
class TranscriptAudioSection extends ConsumerStatefulWidget {
  const TranscriptAudioSection({
    super.key,
    required this.entryId,
    required this.text,
  });

  final String entryId;

  /// The live transcript text; the marks follow its edits.
  final ValueListenable<TextEditingValue> text;

  @override
  ConsumerState<TranscriptAudioSection> createState() =>
      _TranscriptAudioSectionState();
}

class _TranscriptAudioSectionState
    extends ConsumerState<TranscriptAudioSection> {
  bool _expanded = false;
  Timer? _poll;
  int? _current;

  TranscriptAudio? _timedAudio;
  String? _timedText;
  TranscriptTiming? _timing;

  TranscriptTiming _timingOf(TranscriptAudio audio, String text) {
    if (!identical(audio, _timedAudio) || text != _timedText) {
      _timedAudio = audio;
      _timedText = text;
      _timing = audio.timingFor(text);
    }
    return _timing!;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Follows the playback while this entry plays, so the sentence playing
  /// now stays marked.
  void _syncPoll(bool playing) {
    if (playing && _poll == null) {
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
      _tick();
    } else if (!playing && _poll != null) {
      _poll!.cancel();
      _poll = null;
      if (_current != null) setState(() => _current = null);
    }
  }

  void _tick() {
    final timing = _timing;
    final position = ref
        .read(recordingPlaybackProvider.notifier)
        .positionOf(widget.entryId);
    final next = timing == null || position == null
        ? null
        : timing.indexAt(position);
    if (next != _current && mounted) setState(() => _current = next);
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(transcriptAudioProvider(widget.entryId)).value;
    if (audio == null) return const SizedBox.shrink();
    final playing = ref.watch(
      recordingPlaybackProvider.select((key) => key == widget.entryId),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPoll(playing);
    });
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final label = _expanded
        ? l10n.historyAudioHideSentences
        : l10n.historyAudioShowSentences;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.text,
      builder: (context, value, _) {
        final timing = _timingOf(audio, value.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                WpIconButton.ghost(
                  testId: 'history-audio-play',
                  compact: true,
                  icon: playing ? LucideIcons.square : LucideIcons.play,
                  tooltip: playing
                      ? l10n.historyAudioStop
                      : l10n.historyAudioPlay,
                  onPressed: () => unawaited(
                    ref
                        .read(recordingPlaybackProvider.notifier)
                        .toggle(widget.entryId, audio.path),
                  ),
                ),
                const SizedBox(width: WpSpacing.xxs),
                Semantics(
                  button: true,
                  expanded: _expanded,
                  identifier: 'history-audio-toggle',
                  label: label,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: WpRadius.borderSm,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: WpSpacing.xxs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _expanded
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: WpIconSize.xs,
                            color: textMuted,
                          ),
                          const SizedBox(width: WpSpacing.xxs),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: WpTypography.small,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded) _sentenceList(context, l10n, audio, timing),
          ],
        );
      },
    );
  }

  Widget _sentenceList(
    BuildContext context,
    L10n l10n,
    TranscriptAudio audio,
    TranscriptTiming timing,
  ) {
    final textMuted = WpColors.textMuted;
    final unmatched = timing.unmatchedCount;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: WpSpacing.xxs),
      padding: const EdgeInsets.all(WpSpacing.sm),
      decoration: BoxDecoration(
        color: WpColors.surfaceMutedFill,
        borderRadius: WpRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.historyAudioEstimatedHint,
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
          ),
          if (unmatched > 0) ...[
            const SizedBox(height: WpSpacing.xxs),
            Semantics(
              identifier: 'history-audio-unmatched',
              liveRegion: true,
              child: Text(
                l10n.historyAudioUnmatchedCount(unmatched),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  fontWeight: FontWeight.w600,
                  color: WpColors.warning,
                ),
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.xs),
          for (var i = 0; i < timing.sentences.length; i++)
            _SentenceRow(
              index: i,
              sentence: timing.sentences[i],
              current: i == _current,
              onPlay: (start) => unawaited(
                ref
                    .read(recordingPlaybackProvider.notifier)
                    .playFrom(widget.entryId, audio.path, start),
              ),
            ),
        ],
      ),
    );
  }
}

class _SentenceRow extends StatefulWidget {
  const _SentenceRow({
    required this.index,
    required this.sentence,
    required this.current,
    required this.onPlay,
  });

  final int index;
  final TimedSentence sentence;
  final bool current;
  final void Function(Duration start) onPlay;

  @override
  State<_SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<_SentenceRow> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final start = widget.sentence.start;
    final text = widget.sentence.sentence.text;
    final mark = start == null ? '–:––' : formatTimeMark(start);
    final enabled = start != null;
    final semantic = start == null
        ? l10n.historyAudioSentenceNoMarkLabel(text)
        : l10n.historyAudioSentenceLabel(mark, text);
    final color = enabled ? WpColors.textPrimary : WpColors.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.current,
      identifier: 'history-audio-sentence-${widget.index}',
      label: semantic,
      excludeSemantics: true,
      child: WpFocusRing(
        focusNode: _focus,
        child: InkWell(
          focusNode: _focus,
          canRequestFocus: enabled,
          onTap: enabled ? () => widget.onPlay(start) : null,
          borderRadius: WpRadius.borderSm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: widget.current ? WpColors.accentSubtle : null,
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grows with the text size instead of a fixed column width.
                Padding(
                  padding: const EdgeInsets.only(right: WpSpacing.sm),
                  child: Text(
                    mark,
                    style: TextStyle(
                      fontSize: WpTypography.caption,
                      color: WpColors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      color: color,
                      fontWeight: widget.current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
