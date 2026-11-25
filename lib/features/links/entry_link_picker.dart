/// The chooser that typing `[[` opens in an editor (#660): one field, the
/// matching notes, recordings and snippets below it. Before anything is
/// typed it offers the most recently changed entries.
///
/// Keyboard: the caret stays in the field, the arrow keys move the
/// highlight, Enter links the highlighted entry, Escape closes without a
/// link (the typed `[[` stays). The highlighted entry is announced to screen
/// readers, as in the search over every area (#628).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/accessibility/announce.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../widgets/wp_search_field.dart';
import '../history/data/history_lock.dart';
import '../search/data/providers.dart' show contentSearchClockProvider;
import 'data/providers.dart';

/// The name of [kind] as the navigation shows its area.
String entryLinkKindLabel(L10n l10n, EntryLinkKind kind) => switch (kind) {
  EntryLinkKind.note => l10n.entryLinkKindNote,
  EntryLinkKind.recording => l10n.entryLinkKindRecording,
  EntryLinkKind.snippet => l10n.entryLinkKindSnippet,
};

/// The title [entry] goes by, "Untitled" for an entry without words.
String entryLinkTitle(L10n l10n, LinkedEntry entry) =>
    (entry.title?.trim().isNotEmpty ?? false)
    ? entry.title!.trim()
    : l10n.notesUntitled;

/// The picker's list for [query]: recent entries while it is empty.
final entryLinkCandidatesProvider = FutureProvider.autoDispose
    .family<List<LinkedEntry>, ({String query, EntryRef? except})>((ref, args) {
      final db = ref.watch(historyDatabaseProvider);
      final includePrivate = !ref.watch(historyContentHiddenProvider);
      if (args.query.isEmpty) {
        return recentLinkTargets(
          db,
          includePrivate: includePrivate,
          except: args.except,
        );
      }
      return searchLinkTargets(
        db,
        args.query,
        now: ref.read(contentSearchClockProvider)(),
        includePrivate: includePrivate,
        except: args.except,
      );
    });

/// Opens the chooser over [context]. [except] is the entry being written,
/// which never links to itself. Returns the chosen entry, or null.
Future<LinkedEntry?> showEntryLinkPicker(
  BuildContext context, {
  EntryRef? except,
}) {
  final l10n = L10n.of(context);
  return showWpDialog<LinkedEntry>(
    context: context,
    title: l10n.entryLinkPickerTitle,
    size: WpDialogSize.wide,
    content: EntryLinkPickerPanel(except: except),
    actions: [
      WpDialogAction<LinkedEntry>(
        label: l10n.actionCancel,
        testId: 'entry-link-picker-cancel',
        role: WpDialogActionRole.cancel,
      ),
    ],
  );
}

class EntryLinkPickerPanel extends ConsumerStatefulWidget {
  const EntryLinkPickerPanel({super.key, this.except});

  final EntryRef? except;

  @override
  ConsumerState<EntryLinkPickerPanel> createState() =>
      _EntryLinkPickerPanelState();
}

class _EntryLinkPickerPanelState extends ConsumerState<EntryLinkPickerPanel> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final Map<EntryRef, GlobalKey> _rowKeys = {};
  Timer? _debounce;
  String _query = '';
  int _highlight = 0;
  List<LinkedEntry> _shown = const [];
  String? _announced;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final count = _shown.length;
    if (count == 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight((_highlight + 1) % count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight((_highlight - 1 + count) % count);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveHighlight(int index) {
    setState(() => _highlight = index);
    final entry = _shown[index];
    _announce(_spoken(L10n.of(context), entry));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[entry.ref]?.currentContext;
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx, alignment: 0.5));
      }
    });
  }

  void _announce(String text) {
    if (text == _announced) return;
    _announced = text;
    announce(View.of(context), text, Directionality.of(context));
  }

  String _spoken(L10n l10n, LinkedEntry entry) =>
      '${entryLinkKindLabel(l10n, entry.ref.kind)}: '
      '${entryLinkTitle(l10n, entry)}';

  void _take(List<LinkedEntry> entries, L10n l10n) {
    if (identical(entries, _shown)) return;
    _shown = entries;
    _highlight = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _announce(
        entries.isEmpty
            ? l10n.entryLinkPickerEmpty
            : l10n.entryLinkPickerCount(entries.length),
      );
    });
  }

  void _pick(LinkedEntry entry) => Navigator.of(context).pop(entry);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final async = ref.watch(
      entryLinkCandidatesProvider((query: _query, except: widget.except)),
    );
    if (async case AsyncData(:final value)) _take(value, l10n);
    final entries = _shown;
    if (_highlight >= entries.length) _highlight = 0;
    final failed = async.hasError && !async.isLoading;
    final withheld = ref.watch(historyContentHiddenProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSearchField(
          controller: _controller,
          focusNode: _focus,
          hintText: l10n.entryLinkPickerFieldHint,
          semanticsLabel: l10n.entryLinkPickerFieldLabel,
          variant: WpSearchFieldVariant.outlined,
          autofocus: true,
          testId: 'entry-link-picker-field',
          onChanged: _onChanged,
          onSubmitted: (_) {
            if (entries.isNotEmpty) _pick(entries[_highlight]);
          },
        ),
        const SizedBox(height: WpSpacing.sm),
        if (withheld)
          _Note(
            testId: 'entry-link-picker-withheld',
            text: l10n.contentSearchWithheld,
          ),
        if (failed)
          _Note(
            testId: 'entry-link-picker-error',
            text: l10n.contentSearchFailed,
          )
        else if (entries.isEmpty && async.hasValue)
          _Note(
            testId: 'entry-link-picker-empty',
            text: l10n.entryLinkPickerEmpty,
          )
        else ...[
          if (_query.isEmpty && entries.isNotEmpty)
            _Note(
              testId: 'entry-link-picker-recent',
              text: l10n.entryLinkPickerRecent,
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _OptionRow(
                      key: _rowKeys.putIfAbsent(entries[i].ref, GlobalKey.new),
                      entry: entries[i],
                      kindLabel: entryLinkKindLabel(l10n, entries[i].ref.kind),
                      title: entryLinkTitle(l10n, entries[i]),
                      semanticsLabel: _spoken(l10n, entries[i]),
                      highlighted: i == _highlight,
                      onTap: () => _pick(entries[i]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.testId, required this.text});

  final String testId;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: testId,
      child: Padding(
        key: ValueKey(testId),
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
        child: Text(
          text,
          style: TextStyle(
            color: WpColors.textMuted,
            fontSize: WpTypography.small,
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    super.key,
    required this.entry,
    required this.kindLabel,
    required this.title,
    required this.semanticsLabel,
    required this.highlighted,
    required this.onTap,
  });

  final LinkedEntry entry;
  final String kindLabel;
  final String title;
  final String semanticsLabel;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ref = widget.entry.ref;
    final id = 'entry-link-picker-option-${ref.kind.prefix}-${ref.id}';
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).format(widget.entry.changedAt);
    final muted = TextStyle(
      color: WpColors.textMuted,
      fontSize: WpTypography.small,
    );
    return Semantics(
      identifier: id,
      button: true,
      selected: widget.highlighted,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey(id),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: WpListTileSurface(
            variant: WpListTileVariant.panel,
            isHovered: _hovered,
            isFocused: widget.highlighted,
            child: Row(
              children: [
                Text(widget.kindLabel, style: muted),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WpColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Text(date, style: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [showEntryLinkPicker], answered with the link text to insert for the
/// chosen entry (its current title as label), for [WpTextEditor.onPickLink].
Future<String?> pickEntryLinkText(
  BuildContext context, {
  EntryRef? except,
}) async {
  final l10n = L10n.of(context);
  final entry = await showEntryLinkPicker(context, except: except);
  if (entry == null) return null;
  return formatEntryLink(entry.ref, entryLinkTitle(l10n, entry));
}
