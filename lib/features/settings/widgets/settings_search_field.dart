/// Sticky settings search field with debounced query, clear button, and
/// suggestion dropdown that jumps to the matching section on selection.
///
/// Reuses the debounce / clear-button / dropdown pattern from
/// [HistorySearchFilterBar]; keeps the field outside the scroll view so it
/// stays visible while the user scrolls through settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../search/settings_search_provider.dart';

class SettingsSearchField extends ConsumerStatefulWidget {
  const SettingsSearchField({super.key});

  @override
  ConsumerState<SettingsSearchField> createState() =>
      _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends ConsumerState<SettingsSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _showDropdown = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
      });
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay so a tap on a suggestion item fires first
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _showDropdown = false);
      });
    } else if (_controller.text.trim().isNotEmpty) {
      setState(() => _showDropdown = true);
    }
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(settingsSearchQueryProvider.notifier).set('');
    setState(() => _showDropdown = false);
  }

  void _selectEntry(SettingsSearchEntry entry) {
    _clearSearch();
    _focusNode.unfocus();

    // Trigger scroll + brief highlight via the existing infrastructure.
    ref.read(settingsScrollTargetProvider.notifier).set(entry.sectionKey);
    ref.read(settingsHighlightTargetProvider.notifier).set(entry.sectionKey);
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Search field ─────────────────────────────────────────────────
        TextField(
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
                      return InkWell(
                        onTap: () => _selectEntry(entry),
                        child: Padding(
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
