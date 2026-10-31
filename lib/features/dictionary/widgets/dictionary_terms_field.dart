/// The Begriffe ("terms") text field: free-text vocabulary the speech
/// recogniser is nudged towards, saved after a short pause in typing.
///
/// Lives in the dictionary so the terms have one home. The value is the
/// existing `SttSettings.customVocabulary`, so Settings and the dictionary
/// always show the same text.
library;

import 'dart:async';
import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_text_field.dart';

class DictionaryTermsField extends ConsumerStatefulWidget {
  const DictionaryTermsField({super.key, required this.initialValue});

  final String initialValue;

  @override
  ConsumerState<DictionaryTermsField> createState() =>
      _DictionaryTermsFieldState();
}

class _DictionaryTermsFieldState extends ConsumerState<DictionaryTermsField> {
  late final TextEditingController _ctrl;
  Timer? _debounce;
  void Function()? _pendingWrite;

  /// Same real ceiling [SttServerStateNotifier] budgets the combined
  /// `initial_prompt` against — see that constant's doc comment for the
  /// full whisper.cpp derivation (`n_max_text_ctx = 64` → 63 real tokens).
  /// Duplicated here (rather than imported) because the notifier's constant
  /// is `static const int` on a private class member — this field-level
  /// counter only needs the plain number.
  static const int _tokenBudget = 63;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  /// Conservative estimate of [text]'s whisper.cpp token count: its UTF-8
  /// byte length. Whisper's byte-level BPE tokenizer only ever MERGES base
  /// bytes, so the real token count can never exceed this — the estimate
  /// only ever OVER-counts, so a field shown as "under budget" here is
  /// guaranteed to actually stay untruncated by
  /// [SttServerStateNotifier._truncateToRealTokenBudget]. No live model
  /// call needed (this field renders long before any engine may be
  /// loaded), matching the char-based pre-flight backstop's own
  /// conservatism rather than promising per-keystroke exactness a real
  /// tokenizer call could only give async and after a model load.
  static int _estimateTokens(String text) => utf8.encode(text).length;

  @override
  void didUpdateWidget(covariant DictionaryTermsField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    // Save an edit still inside the debounce window instead of dropping it.
    // Deferred: dispose runs inside the widget build, and a provider write
    // there is rejected by Riverpod.
    final pending = _pendingWrite;
    _pendingWrite = null;
    _debounce?.cancel();
    if (pending != null) Future.microtask(pending);
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _save(String value) {
    // Capture the notifier now: `ref` must not be used once the state is
    // disposed, and the flush below can run during dispose.
    final notifier = ref.read(settingsProvider.notifier);
    _pendingWrite = () =>
        notifier.updateSettings((s) => s.copyWith(customVocabulary: value));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    final write = _pendingWrite;
    _pendingWrite = null;
    write?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.bookType,
                size: WpIconSize.sm,
                color: cs.secondary,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.settingsCustomVocabulary,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Padding(
                      // 2px title-subtitle gap: tighter than WpSpacing.xxs so
                      // the pair reads as one unit.
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.settingsCustomVocabularyHint,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: WpColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.sm),
          WpTextField(
            key: const ValueKey('dictionary-terms-field'),
            controller: _ctrl,
            variant: WpTextFieldVariant.form,
            semanticsLabel: l10n.settingsCustomVocabulary,
            hintText: l10n.settingsCustomVocabularyPlaceholder,
            minLines: 2,
            maxLines: 5,
            onChanged: _save,
          ),
          const SizedBox(height: WpSpacing.xxs),
          Builder(
            builder: (context) {
              final estimate = _estimateTokens(_ctrl.text);
              final overBudget = estimate > _tokenBudget;
              final color = overBudget ? cs.error : WpColors.textMuted;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsCustomVocabularyBudgetCounter(
                      estimate,
                      _tokenBudget,
                    ),
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: color,
                    ),
                  ),
                  if (overBudget)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.settingsCustomVocabularyBudgetWarning(
                          _tokenBudget,
                        ),
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: color,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
