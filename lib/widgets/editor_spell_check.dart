/// Spell check of one editor (#670): checks the controller's text a moment
/// after typing stops, hands the misspelled words to the controller for the
/// wavy underline, and serves the context menu and the F7 walk.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/spell/spell_check.dart';
import '../core/spell/spell_words.dart';
import '../features/dictionary/term_store.dart';
import 'editor_smart_action_scope.dart';
import 'find_replace.dart';
import 'parakeet_language_notice.dart' show languageDisplayName;

class WpEditorSpellCheck extends ConsumerStatefulWidget {
  const WpEditorSpellCheck({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  /// The text to check. Underlines need a [WpFindHighlightController]; a
  /// plain controller still gets suggestions and F7.
  final TextEditingController controller;

  /// `false` for read-only views: nothing is checked or underlined.
  final bool enabled;

  final Widget child;

  @override
  ConsumerState<WpEditorSpellCheck> createState() => WpEditorSpellCheckState();

  /// The check around [context], for a field built further down (the long
  /// note editor's active row).
  static WpEditorSpellCheckState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<WpEditorSpellCheckState>();
}

class WpEditorSpellCheckState extends ConsumerState<WpEditorSpellCheck> {
  /// Pause after the last keystroke before the text is checked again.
  static const debounce = Duration(milliseconds: 400);

  Timer? _timer;
  String _checkedText = '';
  List<SpellWord> _errors = const [];
  int _generation = 0;
  final Map<String, List<String>> _suggestions = {};
  String? _language;
  Set<String> _accepted = const {};

  /// Whether a dictionary is active, i.e. the check is on and usable.
  bool get active => widget.enabled && _language != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(WpEditorSpellCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      _clearOn(old.controller, notify: false);
      widget.controller.addListener(_onText);
      _errors = const [];
      _checkedText = '';
      _schedule(immediately: true);
    } else if (old.enabled != widget.enabled) {
      _schedule(immediately: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onText);
    _clearOn(widget.controller, notify: false);
    super.dispose();
  }

  void _clearOn(TextEditingController c, {required bool notify}) {
    if (c is WpFindHighlightController) {
      c.setSpellErrors(const [], notify: notify);
    }
  }

  void _onText() {
    final text = widget.controller.text;
    if (text == _checkedText) return;
    // Carry the underline along until the check has caught up.
    _publish(shiftSpellErrors(_errors, _checkedText, text));
    _checkedText = text;
    _schedule();
  }

  void _schedule({bool immediately = false}) {
    _timer?.cancel();
    _timer = Timer(immediately ? Duration.zero : debounce, _check);
  }

  Future<void> _check() async {
    final generation = ++_generation;
    final language = _language;
    final text = widget.controller.text;
    _checkedText = text;
    if (!active || language == null) {
      _publish(const []);
      return;
    }
    final checker = ref.read(spellCheckerProvider);
    final found = await checker.misspelled(
      language,
      spellWords(text),
      accepted: _accepted,
    );
    if (!mounted || generation != _generation) return;
    if (widget.controller.text != text) return; // a newer check follows
    _publish(found);
  }

  void _publish(List<SpellWord> errors) {
    _errors = errors;
    final c = widget.controller;
    if (c is WpFindHighlightController) {
      c.setSpellErrors([
        for (final e in errors) TextRange(start: e.start, end: e.end),
      ]);
    }
  }

  /// The misspelled word at [offset] of the text, or `null`.
  SpellWord? errorAt(int offset) {
    if (!active) return null;
    final word = spellWordAt(_errors, offset);
    if (word == null) return null;
    final text = widget.controller.text;
    if (word.end > text.length ||
        text.substring(word.start, word.end) != word.text) {
      return null;
    }
    return word;
  }

  /// Suggestions for [word], best first (cached per word).
  Future<List<String>> suggestionsFor(SpellWord word) async {
    final cached = _suggestions[word.text];
    if (cached != null) return cached;
    final language = _language;
    if (language == null) return const [];
    final list = await ref
        .read(spellCheckerProvider)
        .suggest(language, word.text);
    final top = list.take(maxSuggestions).toList(growable: false);
    _suggestions[word.text] = top;
    return top;
  }

  /// Suggestions the context menu and the announcement offer at most.
  static const maxSuggestions = 5;

  /// Replaces [word] with [replacement] and puts the caret after it.
  void replace(SpellWord word, String replacement) {
    final c = widget.controller;
    final text = c.text;
    if (word.end > text.length ||
        text.substring(word.start, word.end) != word.text) {
      return;
    }
    c.value = TextEditingValue(
      text: text.replaceRange(word.start, word.end, replacement),
      selection: TextSelection.collapsed(
        offset: word.start + replacement.length,
      ),
    );
  }

  /// Puts [word] into the app dictionary ("term → term"), so it counts as
  /// correct in every editor from now on.
  Future<void> addToDictionary(SpellWord word) async {
    final container = ProviderScope.containerOf(context, listen: false);
    ref.read(spellCheckerProvider).forget(word.text);
    _publish([
      for (final e in _errors)
        if (e.text.toLowerCase() != word.text.toLowerCase()) e,
    ]);
    await addDictionaryTerms(container, [word.text]);
  }

  /// The next (or previous) error from the current selection, or `null`.
  SpellWord? step({required bool forward}) {
    if (!active) return null;
    final sel = widget.controller.selection;
    final caret = !sel.isValid
        ? 0
        : forward
        ? sel.end
        : sel.start;
    return nextSpellError(_errors, caret, forward: forward);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.enabled
        ? ref.watch(activeSpellLanguageProvider)
        : null;
    // The dictionary is only loaded once a checker is in use.
    final accepted = language == null
        ? const <String>{}
        : ref.watch(spellAcceptedWordsProvider);
    if (language != _language || !identical(accepted, _accepted)) {
      if (language != _language) _suggestions.clear();
      _language = language;
      _accepted = accepted;
      _schedule(immediately: true);
    }
    return widget.child;
  }
}

/// A dictionary tag as the user reads it: "Deutsch (Deutschland)" where the
/// locale catalog knows the region, else the language name plus the region.
String spellLanguageLabel(BuildContext context, String tag) {
  final norm = normalizeSpellTag(tag);
  final parts = norm.split('-');
  final full = LocaleNames.of(context)?.nameOf(norm.replaceAll('-', '_'));
  if (full != null) return full;
  final name = languageDisplayName(context, parts.first);
  return parts.length == 1 ? name : '$name (${parts.skip(1).join('-')})';
}

/// The context menu of an editor field with spell check: for a misspelled
/// word under the caret its suggestions and "Add to dictionary" first, then
/// the usual items. [offsetShift] maps the field's offsets into the text
/// [spell] checks (the long note editor's active row, #670).
Widget spellCheckContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
  WpEditorSpellCheckState? spell, {
  int offsetShift = 0,
  WpEditorContextMenuBuilder? menu,
}) {
  final build =
      menu ?? (c, e, leading) => editorContextMenu(c, e, leading: leading);
  final sel = editableTextState.textEditingValue.selection;
  final word = spell == null || !spell.mounted || !sel.isValid
      ? null
      : spell.errorAt(sel.baseOffset + offsetShift);
  if (word == null) return build(context, editableTextState, const []);
  return _SpellContextMenu(
    editableTextState: editableTextState,
    spell: spell!,
    word: word,
    menu: build,
  );
}

class _SpellContextMenu extends StatefulWidget {
  const _SpellContextMenu({
    required this.editableTextState,
    required this.spell,
    required this.word,
    required this.menu,
  });

  final EditableTextState editableTextState;
  final WpEditorSpellCheckState spell;
  final SpellWord word;
  final WpEditorContextMenuBuilder menu;

  @override
  State<_SpellContextMenu> createState() => _SpellContextMenuState();
}

class _SpellContextMenuState extends State<_SpellContextMenu> {
  late final Future<List<String>> _suggestions = widget.spell.suggestionsFor(
    widget.word,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final editable = widget.editableTextState;
    return FutureBuilder<List<String>>(
      future: _suggestions,
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? const <String>[];
        return widget.menu(context, editable, [
          for (final s in suggestions)
            ContextMenuButtonItem(
              label: s,
              onPressed: () {
                editable.hideToolbar();
                widget.spell.replace(widget.word, s);
              },
            ),
          ContextMenuButtonItem(
            label: l10n.spellCheckAddToDictionary,
            onPressed: () {
              editable.hideToolbar();
              unawaited(widget.spell.addToDictionary(widget.word));
            },
          ),
        ]);
      },
    );
  }
}
