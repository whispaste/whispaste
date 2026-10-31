/// Recognition-language dialog and its row (WP-23e, spec 06 §5.4, ticket IA §5).
///
/// Single select today: the dialog keeps the choice as a list
/// ([WpLanguageSelection.codes]) so WP-23e2 can extend it to several languages
/// without changing the shape of the data.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/config/settings_sections.dart' show SttSettings;
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../core/utils/search_fold.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_search_field.dart';
import '../settings_widgets.dart' show settingsToggle;
import 'wp_settings_group.dart';

/// Value that means "let the engine detect the language".
const String kSttLanguageAuto = 'auto';

/// One language in the grid.
@immutable
class WpLanguageOption {
  const WpLanguageOption({
    required this.code,
    required this.name,
    required this.endonym,
  });

  /// Short code the engine understands, e.g. `de`.
  final String code;

  /// Name in the UI language, e.g. "German".
  final String name;

  /// Name in the language itself, e.g. "Deutsch".
  final String endonym;
}

/// What the user chose. [codes] holds the picked languages; [autoDetect] is
/// the switch. Turning auto-detect on keeps [codes], so switching it back off
/// restores the previous pick.
@immutable
class WpLanguageSelection {
  const WpLanguageSelection({required this.autoDetect, this.codes = const []});

  /// Reads the persisted value: `auto`, or one language code.
  factory WpLanguageSelection.fromSttCode(String code) =>
      code == kSttLanguageAuto
      ? const WpLanguageSelection(autoDetect: true)
      : WpLanguageSelection(autoDetect: false, codes: [code]);

  final bool autoDetect;
  final List<String> codes;

  /// The value to persist: `auto` when auto-detect is on or nothing is chosen,
  /// otherwise the single chosen code.
  String get sttCode =>
      autoDetect || codes.isEmpty ? kSttLanguageAuto : codes.first;
}

/// Opens the dialog and returns the saved selection, or null when cancelled.
///
/// [favorites] are the codes marked with a star. Each star change is reported
/// at once through [onFavoritesChanged] (the dialog's Save only picks the
/// active language), so the caller persists it right away.
Future<WpLanguageSelection?> showWpLanguageDialog({
  required BuildContext context,
  required List<WpLanguageOption> options,
  required WpLanguageSelection initial,
  List<String> favorites = const [],
  ValueChanged<List<String>>? onFavoritesChanged,
}) {
  return showWpFormDialog<WpLanguageSelection>(
    context: context,
    builder: (ctx, animation) => WpLanguageDialog(
      animation: animation,
      options: options,
      initial: initial,
      favorites: favorites,
      onFavoritesChanged: onFavoritesChanged,
      onSave: (selection) => Navigator.of(ctx).pop(selection),
      onCancel: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// Dialog body: auto switch, search, tile grid, selected panel, and the
/// Cancel and Save actions. Esc calls [onCancel].
class WpLanguageDialog extends StatefulWidget {
  const WpLanguageDialog({
    super.key,
    required this.options,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    this.animation,
    this.favorites = const [],
    this.onFavoritesChanged,
  });

  final List<WpLanguageOption> options;
  final WpLanguageSelection initial;
  final ValueChanged<WpLanguageSelection> onSave;
  final VoidCallback onCancel;

  /// Starred codes at the start, at most [SttSettings.maxFavoriteLanguages].
  final List<String> favorites;

  /// Called with the new favorites list after every star change. Null hides
  /// the stars.
  final ValueChanged<List<String>>? onFavoritesChanged;

  /// Route animation of the enclosing dialog; a finished one when omitted.
  final Animation<double>? animation;

  @override
  State<WpLanguageDialog> createState() => _WpLanguageDialogState();
}

/// Height of the tile grid. The grid scrolls inside it.
const double _kGridHeight = 360;

/// Width of the "Selected" panel on the right.
const double _kPanelWidth = 200;

/// Opacity of the grid while auto-detect is on: dimmed, still browsable.
const double _kDimmedOpacity = 0.4;

class _WpLanguageDialogState extends State<WpLanguageDialog> {
  late bool _auto = widget.initial.autoDetect;
  late List<String> _codes = List.of(widget.initial.codes);
  late List<String> _favorites = List.of(widget.favorites);
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// Live availability of Save: auto-detect or at least one language. The
  /// footer is outside the rebuilt body's control, so it reads this notifier.
  late final ValueNotifier<bool> _canSave = ValueNotifier(
    widget.initial.autoDetect || widget.initial.codes.isNotEmpty,
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    _canSave.dispose();
    super.dispose();
  }

  void _setAuto(bool value) => setState(() {
    _auto = value;
    _canSave.value = _auto || _codes.isNotEmpty;
  });

  List<WpLanguageOption> get _visible {
    final q = foldForSearch(_query.trim());
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if (foldForSearch(o.name).contains(q) ||
            foldForSearch(o.endonym).contains(q))
          o,
    ];
  }

  WpLanguageOption? _option(String code) {
    for (final o in widget.options) {
      if (o.code == code) return o;
    }
    return null;
  }

  void _pick(String code) => setState(() {
    _codes = [code];
    _auto = false;
    _canSave.value = true;
  });

  void _toggleFavorite(String code) {
    final next = List.of(_favorites);
    if (next.contains(code)) {
      next.remove(code);
    } else {
      if (next.length >= SttSettings.maxFavoriteLanguages) return;
      next.add(code);
    }
    setState(() => _favorites = next);
    widget.onFavoritesChanged?.call(List.unmodifiable(next));
  }

  void _save() => widget.onSave(
    WpLanguageSelection(autoDetect: _auto, codes: List.unmodifiable(_codes)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final visible = _visible;
    final favoritesFull = _favorites.length >= SttSettings.maxFavoriteLanguages;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: WpFormDialogShell(
        animation: widget.animation ?? kAlwaysCompleteAnimation,
        title: l10n.settingsRecognitionLanguage,
        subtitle: l10n.settingsLanguageDialogSubtitle,
        size: WpDialogSize.wide,
        fields: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                l10n.settingsLanguageAutoDetect,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(width: WpSpacing.sm),
              settingsToggle(
                key: const ValueKey('stt-language-dialog-auto'),
                value: _auto,
                onChanged: _setAuto,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WpSearchField(
                      key: const ValueKey('stt-language-dialog-search'),
                      controller: _searchCtrl,
                      hintText: l10n.settingsLanguageSearchHint,
                      variant: WpSearchFieldVariant.outlined,
                      semanticsLabel: l10n.settingsLanguageSearchHint,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      onClear: () => setState(() => _query = ''),
                    ),
                    const SizedBox(height: WpSpacing.sm),
                    SizedBox(
                      height: _kGridHeight,
                      child: Opacity(
                        key: const ValueKey('stt-language-dialog-grid'),
                        opacity: _auto ? _kDimmedOpacity : 1,
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  l10n.settingsLanguageNoResults,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              )
                            : _TileGrid(
                                options: visible,
                                selectedCode: _auto || _codes.isEmpty
                                    ? null
                                    : _codes.first,
                                onPick: _pick,
                                favorites: _favorites,
                                favoritesFull: favoritesFull,
                                onToggleFavorite:
                                    widget.onFavoritesChanged == null
                                    ? null
                                    : _toggleFavorite,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.md),
              SizedBox(
                width: _kPanelWidth,
                child: _SelectedPanel(
                  key: const ValueKey('stt-language-dialog-selected'),
                  title: l10n.settingsLanguageSelectedTitle,
                  autoLabel: _auto ? l10n.settingsLanguageAutoDetect : null,
                  items: [
                    if (!_auto)
                      for (final code in _codes)
                        _option(code) ??
                            WpLanguageOption(
                              code: code,
                              name: code,
                              endonym: code,
                            ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.onFavoritesChanged != null && favoritesFull)
            Text(
              l10n.settingsLanguageFavoritesLimit,
              key: const ValueKey('stt-language-dialog-favorites-limit'),
              style: theme.textTheme.bodySmall,
            ),
          // Why "Save and close" is greyed out (UIA-SET-10).
          if (!_canSave.value)
            Text(
              l10n.settingsLanguageSavePickOne,
              key: const ValueKey('stt-language-dialog-hint'),
              style: theme.textTheme.bodySmall,
            ),
        ],
        actions: [
          WpDialogAction<Object?>(
            label: l10n.settingsLanguageCancel,
            testId: 'stt-language-dialog-cancel',
            role: WpDialogActionRole.cancel,
            onPressed: widget.onCancel,
          ),
          WpDialogAction<Object?>(
            label: l10n.settingsLanguageSaveAndClose,
            testId: 'stt-language-dialog-save',
            role: WpDialogActionRole.primary,
            enabledWhen: _canSave,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Three-column grid of language tiles. Rows are built by hand so each tile
/// keeps its intrinsic height at large text scales.
class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.options,
    required this.selectedCode,
    required this.onPick,
    this.favorites = const [],
    this.favoritesFull = false,
    this.onToggleFavorite,
  });

  final List<WpLanguageOption> options;
  final String? selectedCode;
  final ValueChanged<String> onPick;
  final List<String> favorites;

  /// True when no further favorite can be added; un-starring stays possible.
  final bool favoritesFull;

  /// Null hides the star buttons.
  final ValueChanged<String>? onToggleFavorite;

  static const int _columns = 3;

  @override
  Widget build(BuildContext context) {
    final rowCount = (options.length + _columns - 1) ~/ _columns;
    final l10n = L10n.of(context);
    return ListView.builder(
      itemCount: rowCount,
      itemBuilder: (context, row) {
        final start = row * _columns;
        return Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < _columns; col++) ...[
                if (col > 0) const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: start + col < options.length
                      ? _languageCell(
                          l10n: l10n,
                          option: options[start + col],
                          selected: options[start + col].code == selectedCode,
                          onPick: onPick,
                          favorite: favorites.contains(
                            options[start + col].code,
                          ),
                          favoriteBlocked:
                              favoritesFull &&
                              !favorites.contains(options[start + col].code),
                          onToggleFavorite: onToggleFavorite,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One grid cell: the language tile plus, when [onToggleFavorite] is set, its
/// star. The star sits beside the tile, not inside it, because the tile's
/// Semantics node excludes its children.
Widget _languageCell({
  required L10n l10n,
  required WpLanguageOption option,
  required bool selected,
  required ValueChanged<String> onPick,
  required bool favorite,
  required bool favoriteBlocked,
  required ValueChanged<String>? onToggleFavorite,
}) {
  final tile = _languageTileNode(
    option: option,
    selected: selected,
    onTap: () => onPick(option.code),
  );
  if (onToggleFavorite == null) return tile;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: tile),
      WpIconButton(
        key: ValueKey('stt-language-dialog-fav-${option.code}'),
        icon: LucideIcons.star,
        color: favorite ? WpColors.accent : WpColors.textMuted,
        tooltip: favorite
            ? l10n.settingsLanguageFavoriteRemove
            : l10n.settingsLanguageFavoriteAdd,
        onPressed: favoriteBlocked ? null : () => onToggleFavorite(option.code),
      ),
    ],
  );
}

/// Semantics node for one grid tile: a button named after the language.
/// Wraps the tile at the call site, so the label is set where the tile is used.
Widget _languageTileNode({
  required WpLanguageOption option,
  required bool selected,
  required VoidCallback onTap,
}) {
  final label = option.name == option.endonym
      ? option.name
      : '${option.name}, ${option.endonym}';
  return Semantics(
    label: label,
    key: ValueKey('stt-language-dialog-tile-${option.code}'),
    button: true,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: _LanguageTile(option: option, selected: selected, onTap: onTap),
  );
}

class _LanguageTile extends StatefulWidget {
  const _LanguageTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final WpLanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LanguageTile> createState() => _LanguageTileState();
}

class _LanguageTileState extends State<_LanguageTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = widget.selected;
    final ink = selected ? WpColors.accent : WpColors.textPrimary;
    return WpFocusRing(
      focusNode: _focusNode,
      radius: WpRadius.sm,
      child: InkWell(
        focusNode: _focusNode,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? WpColors.accentSubtle : WpColors.cardFill,
            borderRadius: BorderRadius.circular(WpRadius.sm),
            border: Border.all(
              color: selected ? WpColors.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.name,
                style: TextStyle(
                  fontFamily: kWpUiFont,
                  fontFamilyFallback: kWpFontFallback,
                  fontSize: WpTypography.subheading,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                option.endonym,
                style: TextStyle(
                  fontFamily: kWpUiFont,
                  fontFamilyFallback: kWpFontFallback,
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w400,
                  color: selected ? WpColors.accent : WpColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Selected" panel: the chosen language, or the auto-detect line.
class _SelectedPanel extends StatelessWidget {
  const _SelectedPanel({
    super.key,
    required this.title,
    required this.autoLabel,
    required this.items,
  });

  final String title;

  /// Shown instead of [items] while auto-detect is on.
  final String? autoLabel;
  final List<WpLanguageOption> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final autoLabel = this.autoLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: WpColors.textMuted,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        if (autoLabel != null)
          Text(autoLabel, style: theme.textTheme.bodyLarge)
        else
          for (final item in items) ...[
            Text(item.name, style: theme.textTheme.titleSmall),
            Text(item.endonym, style: theme.textTheme.bodySmall),
            const SizedBox(height: WpSpacing.sm),
          ],
      ],
    );
  }
}

/// Settings row showing the current recognition language, with a "Change"
/// button that opens [showWpLanguageDialog].
class WpLanguageRow extends StatelessWidget {
  const WpLanguageRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.favorites = const [],
    this.onFavoritesChanged,
  });

  final String title;
  final WpLanguageSelection value;
  final List<WpLanguageOption> options;
  final ValueChanged<WpLanguageSelection> onChanged;
  final List<String> favorites;
  final ValueChanged<List<String>>? onFavoritesChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final currentName = value.autoDetect || value.codes.isEmpty
        ? l10n.settingsLanguageAutoDetect
        : _nameFor(options, value.codes.first);
    return WpSettingsRow(
      rowId: 'stt-language',
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              currentName,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: kWpUiFont,
                fontFamilyFallback: kWpFontFallback,
                fontSize: WpTypography.subheading,
                fontWeight: FontWeight.w500,
              ).copyWith(color: WpColors.textSecondary),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          WpButton(
            key: const ValueKey('stt-language-row-change'),
            label: l10n.settingsLanguageChange,
            variant: WpButtonVariant.secondary,
            size: WpButtonSize.dense,
            onPressed: () async {
              final picked = await showWpLanguageDialog(
                context: context,
                options: options,
                initial: value,
                favorites: favorites,
                onFavoritesChanged: onFavoritesChanged,
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ],
      ),
    );
  }
}

String _nameFor(List<WpLanguageOption> options, String code) {
  for (final o in options) {
    if (o.code == code) return o.name;
  }
  return code;
}
