import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import 'settings_widgets.dart';
import 'widgets/wp_settings_group.dart';

/// Longest accepted trigger word. A spoken word is short by nature.
const int kSnippetPickerTriggerMaxLength = 64;

/// How long typing must pause before the word is written.
const Duration _commitDelay = Duration(milliseconds: 600);

/// A trigger word is one spoken word: no line breaks or other control
/// characters.
final TextInputFormatter _noControlCharacters =
    FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'));

/// Settings row for the spoken trigger word of the Snippet-Picker (UX-030).
///
/// The word is a global setting that changes rarely, so it lives next to the
/// picker hotkey in General › Tastenkürzel and not on the Snippets page. An
/// empty word switches the spoken trigger off.
///
/// A typed word is never lost: it is written after a short pause, when the row
/// leaves the page, and when the app is paused. An external change (e.g. a
/// settings import) replaces the text and drops the pending typing.
class SnippetPickerTriggerRow extends ConsumerStatefulWidget {
  const SnippetPickerTriggerRow({super.key, required this.trigger});

  /// The stored trigger word.
  final String trigger;

  @override
  ConsumerState<SnippetPickerTriggerRow> createState() =>
      _SnippetPickerTriggerRowState();
}

class _SnippetPickerTriggerRowState
    extends ConsumerState<SnippetPickerTriggerRow>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;

  /// Captured once: a write during dispose must not go through `ref`.
  late final SettingsNotifier _settings;

  /// The last value written to the store, or received from it.
  late String _committed;

  /// Typed but not yet written.
  String? _pending;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.trigger);
    _settings = ref.read(settingsProvider.notifier);
    _committed = widget.trigger;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(SnippetPickerTriggerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Our own commit echoing back: keep whatever the user typed since.
    if (widget.trigger == _committed) return;
    // External change: it wins over pending typing.
    _debounce?.cancel();
    _debounce = null;
    _pending = null;
    _committed = widget.trigger;
    _controller.text = widget.trigger;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    final pending = _pending;
    if (pending != null) {
      // Written after the element is gone, so it must not depend on `ref`.
      Future<void>.microtask(() => _write(pending));
    }
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _pending = value;
    _debounce?.cancel();
    _debounce = Timer(_commitDelay, _flush);
  }

  /// Writes the pending word now. Does nothing when nothing is pending.
  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    final value = _pending;
    if (value == null) return;
    _pending = null;
    _committed = value;
    _write(value);
  }

  void _write(String value) {
    // Raw value on purpose: the dispatcher normalizes both sides via
    // `normalizeForExactMatch` (see `snippet_picker_dispatch.dart`).
    unawaited(
      _settings.updateSettings(
        (s) => s.copyWithSections(
          behavior: s.behavior.copyWith(snippetPickerTrigger: value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: 'general-snippet-picker-trigger',
      title: l10n.snippetsPickerTriggerLabel,
      subtitle: l10n.snippetsPickerTriggerSubtitle,
      trailing: Semantics(
        identifier: 'settings-general-snippet-picker-trigger-field',
        child: settingsTextField(
          context: context,
          controller: _controller,
          hintText: l10n.snippetsPickerTriggerHint,
          onChanged: _onChanged,
          semanticLabel: l10n.snippetsPickerTriggerLabel,
          maxLength: kSnippetPickerTriggerMaxLength,
          inputFormatters: [_noControlCharacters],
        ),
      ),
    );
  }
}
