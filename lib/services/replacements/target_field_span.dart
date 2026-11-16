/// Learning from edits made in the target app after a paste (issue #384).
/// Pure logic: the shape of one native read of the target field and the
/// alignment that finds the pasted words inside the read span. No channel,
/// no clock, no database.
///
/// The native side (channel `com.whispaste.inserted_span`, method
/// `readInsertedSpan`, same contract on macOS, Windows and Linux) returns only
/// a bounded section around the caret of the focused field (the pasted length
/// plus [targetFieldSpanSlack] on each side), never the whole document.
/// Password fields are never read.
library;

import 'correction_word_diff.dart';

/// Slack in characters the native side reads beyond the pasted length, so a
/// correction that made the text longer still fits into the section.
const int targetFieldSpanSlack = 64;

/// Transcripts longer than this are not watched: the read span would grow
/// with them, and a correction of one to four words in a long text is better
/// made in the history entry.
const int targetFieldMaxInsertedChars = 2000;

/// Why a target field could not be read, grouped for the learning log.
/// The runners answer finer `reason` codes; [fromCode] maps them.
enum TargetFieldUnreadableReason {
  /// The OS denied reading (macOS Accessibility not granted, no AT-SPI bus).
  permission,

  /// The Mac App Store sandbox blocks the Accessibility API for other apps.
  sandbox,

  /// The focused field is a password field. Never read.
  password,

  /// No focused element, or WhisPaste itself has the focus.
  noFocus,

  /// The focused element exposes no text or no caret to accessibility (many
  /// terminals and canvas-drawn editors).
  noText,

  /// The platform runner has no handler.
  unsupported,

  /// A read is already running (Windows allows two at once). Transient.
  busy,

  /// The native read failed or did not answer in time.
  error;

  /// Maps a runner `reason` code (channel contract, see
  /// `target_field_learning.dart`) to its group. Unknown codes are errors.
  static TargetFieldUnreadableReason fromCode(Object? code) => switch (code) {
    'permission_missing' => permission,
    'sandbox' => sandbox,
    'password_field' => password,
    'no_focus' || 'own_window' => noFocus,
    'no_text_pattern' || 'no_caret' => noText,
    'unsupported' => unsupported,
    'busy' => busy,
    _ => error,
  };
}

/// The paths that answer a field without a caret (macOS, Linux).
const _noCaretPatterns = {'ax_value', 'atspi_tail'};

/// One answer of `readInsertedSpan`.
class TargetFieldRead {
  const TargetFieldRead.readable({
    required String this.text,
    this.matchesExpected = false,
    this.hasCaret = true,
  }) : reason = null;

  const TargetFieldRead.unreadable(TargetFieldUnreadableReason this.reason)
    : text = null,
      matchesExpected = false,
      hasCaret = false;

  /// Parses the channel reply. Anything malformed counts as
  /// [TargetFieldUnreadableReason.error], never as an empty readable field.
  factory TargetFieldRead.fromReply(Object? reply) {
    if (reply is! Map) {
      return const TargetFieldRead.unreadable(
        TargetFieldUnreadableReason.error,
      );
    }
    final text = reply['text'];
    if (reply['readable'] == true && text is String) {
      return TargetFieldRead.readable(
        text: text,
        matchesExpected: reply['matchesExpected'] == true,
        hasCaret: !_noCaretPatterns.contains(reply['pattern']),
      );
    }
    return TargetFieldRead.unreadable(
      TargetFieldUnreadableReason.fromCode(reply['reason']),
    );
  }

  /// The bounded section around the caret; only set when readable.
  final String? text;

  /// Whether [text] still contains the pasted text (nothing changed).
  final bool matchesExpected;

  /// Whether [text] was found from the caret. Without one it is some section
  /// of the field (the tail, for example), which says nothing about what
  /// stands in front of the next insert.
  final bool hasCaret;

  /// Why the field could not be read; only set when unreadable.
  final TargetFieldUnreadableReason? reason;

  bool get readable => text != null;
}

/// Words of context kept in front of each change.
const int targetEditContextWords = 3;

/// One change the user made inside the pasted section: the words that were
/// there and the words that replaced them, plus a few raw tokens in front of
/// the change (with punctuation) as context.
class TargetEditPair {
  const TargetEditPair({
    required this.sourceText,
    required this.targetText,
    required this.contextBefore,
  });

  final String sourceText;
  final String targetText;
  final String contextBefore;

  @override
  bool operator ==(Object other) =>
      other is TargetEditPair &&
      other.sourceText == sourceText &&
      other.targetText == targetText &&
      other.contextBefore == contextBefore;

  @override
  int get hashCode => Object.hash(sourceText, targetText, contextBefore);

  @override
  String toString() =>
      'TargetEditPair("$sourceText" -> "$targetText" after "$contextBefore")';
}

typedef _Token = ({String raw, String text, String key, bool word});

List<_Token> _tokensOf(String text) => [
  for (final raw in text.split(RegExp(r'\s+', unicode: true)))
    if (raw.isNotEmpty)
      switch (wordsOf(raw)) {
        [final w, ...] => (raw: raw, text: w.text, key: w.key, word: true),
        _ => (raw: raw, text: '', key: '', word: false),
      },
];

/// The changes the user made to the pasted [inserted] text, as found in the
/// read [span] of the target field.
///
/// The pasted section is anchored by its words, not by the caret: foreign
/// text before and after is cut off wherever the user clicked or moved the
/// caret. Each changed place gives its own pair (old -> new). Pure insertions
/// and deletions are no replacement and give nothing; words added after the
/// pasted text (writing on) are outside the section. A change of case alone
/// counts only mid-sentence, where a capital marks a name, not at a sentence
/// start.
///
/// Returns `null` when the pasted text is not recognisable in the span any
/// more (fewer than half of its words still match, or the span is empty),
/// and an empty list when nothing was changed.
List<TargetEditPair>? targetEditPairs(String inserted, String span) {
  final a = wordsOf(inserted);
  final tokens = _tokensOf(span);
  final wordIndex = [
    for (var i = 0; i < tokens.length; i++)
      if (tokens[i].word) i,
  ];
  final b = [
    for (final i in wordIndex) (text: tokens[i].text, key: tokens[i].key),
  ];
  if (a.isEmpty || b.isEmpty) return null;
  if (a.length * b.length > correctionMaxDiffCells) return null;

  final matches = longestCommonWordPairs(a, b);
  if (matches.isEmpty || matches.length * 2 < a.length) return null;

  final (firstA, firstB) = matches.first;
  final (lastA, lastB) = matches.last;
  final start = (firstB - firstA).clamp(0, b.length);
  final end = (lastB + (a.length - 1 - lastA) + 1).clamp(start, b.length);

  String context(int bIndex) {
    final tokenAt = bIndex < b.length ? wordIndex[bIndex] : tokens.length;
    final from = (tokenAt - targetEditContextWords).clamp(0, tokenAt);
    return [for (var t = from; t < tokenAt; t++) tokens[t].raw].join(' ');
  }

  final pairs = <TargetEditPair>[];
  var ia = 0;
  var ib = start;
  for (final (ma, mb) in [...matches, (a.length, end)]) {
    final source = [for (var i = ia; i < ma; i++) a[i].text];
    final target = [for (var j = ib; j < mb && j < end; j++) b[j].text];
    if (source.isNotEmpty && target.isNotEmpty) {
      pairs.add(
        TargetEditPair(
          sourceText: source.join(' '),
          targetText: target.join(' '),
          contextBefore: context(ib),
        ),
      );
    }
    if (ma < a.length && a[ma].text != b[mb].text) {
      final ctx = context(mb);
      if (_isMidSentence(ctx)) {
        pairs.add(
          TargetEditPair(
            sourceText: a[ma].text,
            targetText: b[mb].text,
            contextBefore: ctx,
          ),
        );
      }
    }
    ia = ma + 1;
    ib = mb + 1;
  }
  return pairs;
}

/// Whether a word after [context] stands inside a sentence: there is text in
/// front of it and that text does not end a sentence.
bool _isMidSentence(String context) {
  final trimmed = context.trimRight();
  if (trimmed.isEmpty) return false;
  return !_sentenceEnd.hasMatch(trimmed);
}

final RegExp _sentenceEnd = RegExp(r'[.!?…:]["»“”’)\]]*$');
