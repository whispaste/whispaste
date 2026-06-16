/// Sticky settings search field with debounced query, clear button, and
/// suggestion dropdown that jumps to the matching section on selection.
///
/// Reuses the debounce / clear-button / dropdown pattern from
/// [HistorySearchFilterBar]; keeps the field outside the scroll view so it
/// stays visible while the user scrolls through settings.
///
/// Keyboard accessibility (slice 09):
/// - An external [focusNode] lets the parent page wire Ctrl+F / Cmd+F focus.
/// - When the dropdown is visible: ArrowDown/Up navigate suggestions, Enter
///   selects the highlighted suggestion, Escape clears and closes.
/// - The field carries a Semantics label; a live region announces result counts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../search/settings_search_provider.dart';

class SettingsSearchField extends ConsumerStatefulWidget {
  const SettingsSearchField({super.key, this.focusNode});

  /// Optional external [FocusNode]. When provided the parent owns the node's
  /// lifecycle; when omitted the widget creates and disposes its own.
  final FocusNode? focusNode;

  @override
  ConsumerState<SettingsSearchField> createState() =>
      _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends ConsumerState<SettingsSearchField> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _ownsNode = false;
  Timer? _debounce;
  bool _showDropdown = false;

  /// Index of the keyboard-highlighted suggestion; -1 means none.
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _ownsNode = false;
    } else {
      _focusNode = FocusNode();
      _ownsNode = true;
    }
    _focusNode.onKeyEvent = _handleKeyEvent;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.onKeyEvent = null;
    _controller.dispose();
    if (_ownsNode) _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Key event handler — arrow/enter/escape for dropdown navigation
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Escape: close dropdown / blur field
    if (key == LogicalKeyboardKey.escape) {
      if (_showDropdown) {
        _clearSearch();
      } else {
        _focusNode.unfocus();
      }
      return KeyEventResult.handled;
    }

    // Arrow / Enter: only when the dropdown has entries
    if (!_showDropdown) return KeyEventResult.ignored;
    final matches = ref.read(settingsSearchMatchesProvider);
    if (matches.isEmpty) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = _highlightedIndex < 0
            ? 0
            : (_highlightedIndex + 1) % matches.length;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = _highlightedIndex <= 0
            ? matches.length - 1
            : _highlightedIndex - 1;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < matches.length) {
        _selectEntry(matches[_highlightedIndex]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Text / focus helpers
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ref.read(settingsSearchQueryProvider.notifier).set(_controller.text);
    });
    // Show dropdown immediately while typing (populated after debounce resolves)
    if (mounted) {
      setState(() {
        _showDropdown = _controller.text.trim().isNotEmpty;
        _highlightedIndex = -1; // reset on every text change
      });
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay so a tap on a suggestion item fires first
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() {
          _showDropdown = false;
          _highlightedIndex = -1;
        });
      });
    } else if (_controller.text.trim().isNotEmpty) {
      setState(() => _showDropdown = true);
    }
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(settingsSearchQueryProvider.notifier).set('');
    setState(() {
      _showDropdown = false;
      _highlightedIndex = -1;
    });
  }

  void _selectEntry(SettingsSearchEntry entry) {
    _clearSearch();
    _focusNode.unfocus();

    // Trigger scroll + brief highlight via the existing infrastructure.
    ref.read(settingsScrollTargetProvider.notifier).set(entry.sectionKey);
    ref.read(settingsHighlightTargetProvider.notifier).set(entry.sectionKey);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surface = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderCol = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;

    // Read current matches from the provider (populated after debounce)
    final matches = ref.watch(settingsSearchMatchesProvider);
    final rawQuery = _controller.text;

    // Announce result count to screen readers whenever it changes.
    final view = View.of(context);
    ref.listen<List<SettingsSearchEntry>>(settingsSearchMatchesProvider, (
      _,
      next,
    ) {
      if (!mounted) return;
      final query = ref.read(settingsSearchQueryProvider).trim();
      if (query.isNotEmpty) {
        SemanticsService.sendAnnouncement(
          view,
          l10n.settingsSearchResultCount(next.length),
          Directionality.of(context),
        );
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Search field ─────────────────────────────────────────────────
        Semantics(
          label: l10n.settingsSearchFieldLabel,
          textField: true,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: l10n.settingsSearchHint,
              prefixIcon: Icon(
                LucideIcons.search,
                size: WpIconSize.sm,
                color: textMuted,
              ),
              suffixIcon: rawQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: WpIconSize.sm,
                        color: textMuted,
                      ),
                      tooltip: l10n.historyClearSearch,
                      onPressed: _clearSearch,
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xs + 2,
              ),
            ),
            onChanged: (_) {}, // handled by controller listener
          ),
        ),

        // ── Invisible live region: announces result count to screen readers ─
        Semantics(
          liveRegion: true,
          label: matches.isNotEmpty
              ? l10n.settingsSearchResultCount(matches.length)
              : '',
          child: const SizedBox.shrink(),
        ),

        // ── Suggestion dropdown ──────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _showDropdown && matches.isNotEmpty
              ? Container(
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: WpRadius.borderSm,
                    border: Border.all(color: borderCol),
                    boxShadow: WpShadows.subtle,
                  ),
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: WpSpacing.xxs,
                    ),
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (ctx, i) {
                      final entry = matches[i];
                      final isHighlighted = i == _highlightedIndex;
                      return Semantics(
                        button: true,
                        selected: isHighlighted,
                        child: InkWell(
                          onTap: () => _selectEntry(entry),
                          child: Container(
                            color: isHighlighted
                                ? accent.withValues(alpha: 0.12)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.md,
                              vertical: WpSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.settings2,
                                  size: WpIconSize.xs,
                                  color: accent,
                                ),
                                const SizedBox(width: WpSpacing.xs),
                                Expanded(
                                  child: Text(
                                    entry.title(
                                      Localizations.localeOf(
                                        context,
                                      ).languageCode,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? WpColorsDark.textPrimary
                                          : WpColorsLight.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(
                                  LucideIcons.arrowRight,
                                  size: WpIconSize.xs,
                                  color: textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
