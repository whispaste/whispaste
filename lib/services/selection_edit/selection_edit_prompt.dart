/// Prompt building for "edit selection by voice"
/// (`.scratch/voice-selection-edit/`).
///
/// The overlay is not clickable per element, so the quick actions
/// (shorten / improve / translate) are triggered by speaking exactly one
/// keyword in any of the four UI locales (en/de/he/ru). Anything else is a
/// free-form instruction passed to the engine together with the selection.
library;

import '../smart_mode/smart_mode_presets.dart';

/// The spoken quick actions every UI locale supports.
enum SelectionEditQuickAction { shorten, improve, translate }

/// The engine input for one selection edit.
class SelectionEditPrompt {
  const SelectionEditPrompt({
    required this.systemPrompt,
    required this.userText,
    this.quickAction,
  });

  final String systemPrompt;
  final String userText;

  /// The matched quick action, or `null` for a free-form instruction.
  final SelectionEditQuickAction? quickAction;
}

// Keywords are compared after [_normalize] (lower-cased, punctuation and
// surrounding whitespace stripped), so "Kürzer." and "kürzer" both match.
const Map<SelectionEditQuickAction, Set<String>> _keywords = {
  SelectionEditQuickAction.shorten: {
    // en
    'shorten', 'shorter', 'make it shorter', 'make shorter',
    // de
    'kürzen', 'kürzer', 'kürze', 'mach kürzer', 'mach es kürzer',
    // he
    'קצר', 'לקצר', 'תקצר', 'קצר יותר',
    // ru
    'короче', 'сократи', 'сократить', 'сделай короче',
  },
  SelectionEditQuickAction.improve: {
    // en
    'improve', 'improve it', 'make it better', 'polish',
    // de
    'verbessern', 'verbessere', 'verbessere es', 'besser', 'mach es besser',
    // he
    'שפר', 'לשפר', 'תשפר',
    // ru
    'улучши', 'улучшить', 'сделай лучше',
  },
  SelectionEditQuickAction.translate: {
    // en
    'translate', 'translate it',
    // de
    'übersetzen', 'übersetze', 'übersetz',
    // he
    'תרגם', 'לתרגם', 'תתרגם',
    // ru
    'переведи', 'перевести',
  },
};

final RegExp _punctuation = RegExp(r'''[.,!?;:…"'«»„“”‚‘’()\[\]]''');
final RegExp _whitespace = RegExp(r'\s+');

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(_punctuation, ' ')
    .trim()
    .replaceAll(_whitespace, ' ');

/// The quick action [instruction] names, or `null` when it is a free-form
/// instruction (or empty).
SelectionEditQuickAction? selectionEditQuickActionFor(String instruction) {
  final normalized = _normalize(instruction);
  if (normalized.isEmpty) return null;
  for (final MapEntry(:key, :value) in _keywords.entries) {
    if (value.contains(normalized)) return key;
  }
  return null;
}

/// System prompt for a free-form instruction. Kept in English regardless of
/// UI locale, like every other Smart Mode prompt (ADR 0006).
const String selectionEditInstructionSystemPrompt =
    'You edit text. Apply the instruction to the text between <text> and '
    '</text>. Keep the exact same language as the text unless the '
    'instruction explicitly asks for a different one. Output ONLY the edited '
    'text — no explanation, no quotes, no tags.';

const String selectionEditShortenSystemPrompt =
    'Shorten this text: remove redundancy and filler while preserving the '
    'core meaning and every important fact. Do not translate it — keep the '
    'exact same language as the input. Output ONLY the shortened text, no '
    'explanation.';

const String selectionEditImproveSystemPrompt =
    'Improve this text: fix spelling, grammar and punctuation and make it '
    'read clearly and fluently, while preserving its meaning, tone and every '
    'important fact. Do not translate it — keep the exact same language as '
    'the input. Output ONLY the improved text, no explanation.';

String selectionEditTranslateSystemPrompt(SmartModeTargetLanguage target) =>
    'Translate this text into ${target.languageName}. If it is already in '
    '${target.languageName}, return it unchanged. Output ONLY the translated '
    'text, no explanation.';

/// Builds the engine input for applying [instruction] to [selection].
///
/// A quick action sends the bare selection with a dedicated prompt (better
/// results from small local models than an instruction wrapper); a
/// free-form instruction sends both, with the selection explicitly
/// delimited so the model never mistakes the instruction for text to edit.
SelectionEditPrompt buildSelectionEditPrompt({
  required String instruction,
  required String selection,
  SmartModeTargetLanguage translateTarget = SmartModeTargetLanguage.english,
}) {
  final action = selectionEditQuickActionFor(instruction);
  return switch (action) {
    SelectionEditQuickAction.shorten => SelectionEditPrompt(
      systemPrompt: selectionEditShortenSystemPrompt,
      userText: selection,
      quickAction: action,
    ),
    SelectionEditQuickAction.improve => SelectionEditPrompt(
      systemPrompt: selectionEditImproveSystemPrompt,
      userText: selection,
      quickAction: action,
    ),
    SelectionEditQuickAction.translate => SelectionEditPrompt(
      systemPrompt: selectionEditTranslateSystemPrompt(translateTarget),
      userText: selection,
      quickAction: action,
    ),
    null => SelectionEditPrompt(
      systemPrompt: selectionEditInstructionSystemPrompt,
      userText:
          'Instruction: ${instruction.trim()}\n\n<text>\n$selection\n</text>',
    ),
  };
}
