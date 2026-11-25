/// Recognition-language dialog and its row (ticket, spec 06 §5.4, ticket IA §5;
/// favorites only by star in the dialog since #1610).
///
/// Single selection for a fixed language; optional multiple selection for
/// the expected languages used by automatic recognition.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/config/language_favorites.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../core/utils/search_fold.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_row_action.dart';
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

  /// Line shown under [name]: the [endonym], or null when it would only
  /// repeat the name ("Deutsch / Deutsch") or show a bare code ("ga").
  String? get secondLine {
    final e = endonym.trim();
    if (e.isEmpty) return null;
    final folded = e.toLowerCase();
    if (folded == name.trim().toLowerCase()) return null;
    if (folded == code.toLowerCase()) return null;
    return e;
  }
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
/// [favorites] are the codes marked with a star, in their stored order. Each
/// star change is reported at once through [onFavoritesChanged] (the dialog's
/// Save only picks the active language), so the caller persists it right
/// away; Cancel does not undo a star.
Future<WpLanguageSelection?> showWpLanguageDialog({
  required BuildContext context,
  required List<WpLanguageOption> options,
  required WpLanguageSelection initial,
  bool multiple = false,
  List<String> favorites = const [],
  ValueChanged<List<String>>? onFavoritesChanged,
  String? title,
  String? subtitle,
  String? emptySelectionLabel,
}) {
  return showWpFormDialog<WpLanguageSelection>(
    context: context,
    builder: (ctx, animation) => WpLanguageDialog(
      animation: animation,
      multiple: multiple,
      title: title,
      subtitle: subtitle,
      emptySelectionLabel: emptySelectionLabel,
      options: options,
      initial: initial,
      favorites: favorites,
      onFavoritesChanged: onFavoritesChanged,
      onSave: (selection) => Navigator.of(ctx).pop(selection),
      onCancel: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// Dialog body (#1610): search and the auto switch on one line, then one
/// scrolling list with the favorites group on top and all languages below,
/// the current choice under it, and the Cancel and Save actions. Esc calls
/// [onCancel].
///
/// The star on a tile is the only place to set or remove a favorite (the
/// separate favorites row in Settings is gone). A new favorite goes to the
/// end of the list, so the favorites group shows the order the quick pick,
/// the tray menu and the cycle hotkey use.
class WpLanguageDialog extends StatefulWidget {
  const WpLanguageDialog({
    super.key,
    required this.options,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    this.animation,
    this.multiple = false,
    this.favorites = const [],
    this.onFavoritesChanged,
    this.title,
    this.subtitle,
    this.emptySelectionLabel,
  });

  final bool multiple;

  /// Heading and line below it; the recognition-language texts when null.
  /// Other pickers of languages (the Hugging-Face-Suche, #2193) name their
  /// own purpose.
  final String? title;
  final String? subtitle;

  /// What "nothing chosen" means in the multiple mode; "detect
  /// automatically" when null.
  final String? emptySelectionLabel;
  final List<WpLanguageOption> options;
  final WpLanguageSelection initial;
  final ValueChanged<WpLanguageSelection> onSave;
  final VoidCallback onCancel;

  /// Starred codes at the start, at most [maxFavoriteLanguages].
  final List<String> favorites;

  /// Called with the new favorites list after every star change. Null hides
  /// the stars and the favorites group.
  final ValueChanged<List<String>>? onFavoritesChanged;

  /// Route animation of the enclosing dialog; a finished one when omitted.
  final Animation<double>? animation;

  @override
  State<WpLanguageDialog> createState() => _WpLanguageDialogState();
}

/// Height of the language list; the list scrolls inside it.
const double _kGridHeight = 360;

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
    widget.multiple ||
        widget.initial.autoDetect ||
        widget.initial.codes.isNotEmpty,
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

  WpLanguageOption _option(String code) {
    for (final o in widget.options) {
      if (o.code == code) return o;
    }
    return WpLanguageOption(code: code, name: code, endonym: '');
  }

  void _pick(String code) => setState(() {
    if (widget.multiple) {
      _codes.contains(code) ? _codes.remove(code) : _codes.add(code);
    } else {
      _codes = [code];
    }
    _auto = false;
    _canSave.value = true;
  });

  void _toggleFavorite(String code) {
    final change = toggleFavoriteLanguage(_favorites, code);
    if (!change.applied) return;
    setState(() => _favorites = List.of(change.favorites));
    widget.onFavoritesChanged?.call(change.favorites);
  }

  void _save() => widget.onSave(
    WpLanguageSelection(autoDetect: _auto, codes: List.unmodifiable(_codes)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final visible = _visible;
    final stars = widget.onFavoritesChanged != null;
    final favoritesFull = _favorites.length >= maxFavoriteLanguages;
    final selectedCode = _auto || _codes.isEmpty ? null : _codes.first;
    // While searching the list is one flat set of matches: the favorites
    // are among them, a second copy on top would only repeat them.
    final showFavoritesGroup = stars && _query.trim().isEmpty;

    _LanguageCell cell(WpLanguageOption option, {required String group}) =>
        _LanguageCell(
          key: ValueKey('stt-language-dialog-$group-cell-${option.code}'),
          option: option,
          keyPrefix: group == 'all' ? '' : '$group-',
          selected: widget.multiple
              ? _codes.contains(option.code)
              : option.code == selectedCode,
          onPick: _pick,
          favorite: _favorites.contains(option.code),
          favoriteBlocked: favoritesFull && !_favorites.contains(option.code),
          onToggleFavorite: stars ? _toggleFavorite : null,
        );

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
        title: widget.title ?? l10n.settingsRecognitionLanguage,
        subtitle:
            widget.subtitle ??
            (widget.multiple
                ? l10n.settingsSpokenLanguagesDialogHint
                : l10n.settingsLanguageDialogSubtitle),
        size: WpDialogSize.wide,
        fields: [
          Row(
            children: [
              Expanded(
                child: WpSearchField(
                  key: const ValueKey('stt-language-dialog-search'),
                  controller: _searchCtrl,
                  hintText: l10n.settingsLanguageSearchHint,
                  variant: WpSearchFieldVariant.outlined,
                  semanticsLabel: l10n.settingsLanguageSearchHint,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () => setState(() => _query = ''),
                ),
              ),
              const SizedBox(width: WpSpacing.lg),
              if (!widget.multiple) ...[
                // The switch carries this name itself; read once, not twice.
                ExcludeSemantics(
                  child: Text(
                    l10n.settingsLanguageAutoDetect,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                settingsToggle(
                  label: l10n.settingsLanguageAutoDetect,
                  key: const ValueKey('stt-language-dialog-auto'),
                  value: _auto,
                  onChanged: _setAuto,
                ),
              ],
            ],
          ),
          const SizedBox(height: WpSpacing.md),
          SizedBox(
            height: _kGridHeight,
            child: Opacity(
              key: const ValueKey('stt-language-dialog-grid'),
              opacity: _auto && !widget.multiple ? _kDimmedOpacity : 1,
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        l10n.settingsLanguageNoResults,
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  // A plain ListView with keyed rows: a star that adds a row
                  // to the favorites group above does not hand the focused
                  // star's row to another language.
                  : ListView(
                      children: [
                        if (showFavoritesGroup) ...[
                          _GroupHeader(
                            key: const ValueKey(
                              'stt-language-dialog-favorites-heading',
                            ),
                            title: l10n.settingsLanguageFavorites,
                            hint: _favorites.isEmpty
                                ? l10n.settingsLanguageFavoritesEmpty(
                                    maxFavoriteLanguages,
                                  )
                                : l10n.settingsLanguageFavoritesHint,
                            note: favoritesFull
                                ? l10n.settingsLanguageFavoritesLimit(
                                    maxFavoriteLanguages,
                                  )
                                : null,
                            noteKey: const ValueKey(
                              'stt-language-dialog-favorites-limit',
                            ),
                          ),
                          ..._tileRows(
                            group: 'favorites',
                            cells: [
                              for (final code in _favorites)
                                cell(_option(code), group: 'favorites'),
                            ],
                          ),
                          _GroupHeader(
                            key: const ValueKey(
                              'stt-language-dialog-all-heading',
                            ),
                            title: l10n.settingsLanguageAllLanguages,
                            topGap: true,
                          ),
                        ],
                        ..._tileRows(
                          group: 'all',
                          cells: [
                            for (final o in visible) cell(o, group: 'all'),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          _SelectedLine(
            key: const ValueKey('stt-language-dialog-selected'),
            title: l10n.settingsLanguageSelectedTitle,
            value: widget.multiple && _codes.isNotEmpty
                ? _codes.map((c) => _option(c).name).join(', ')
                : selectedCode == null
                ? (widget.multiple ? widget.emptySelectionLabel : null) ??
                      l10n.settingsLanguageAutoDetect
                : _option(selectedCode).name,
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

/// Tiles per row in both groups.
const int _kColumns = 3;

/// [cells] cut into rows of [_kColumns]. Tiles of one row share the height
/// of the tallest, and every tile reserves its second line, so rows with and
/// without an endonym ("English") are equally tall.
List<Widget> _tileRows({required String group, required List<Widget> cells}) {
  return [
    for (var start = 0; start < cells.length; start += _kColumns)
      Padding(
        key: ValueKey('stt-language-dialog-$group-row-${start ~/ _kColumns}'),
        padding: const EdgeInsets.only(bottom: WpSpacing.xs),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var col = 0; col < _kColumns; col++) ...[
                if (col > 0) const SizedBox(width: WpSpacing.xs),
                Expanded(
                  child: start + col < cells.length
                      ? cells[start + col]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
  ];
}

/// Heading of a group in the language list, with an optional [hint] line
/// and a [note] (the favorites limit).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    super.key,
    required this.title,
    this.hint,
    this.note,
    this.noteKey,
    this.topGap = false,
  });

  final String title;
  final String? hint;
  final String? note;
  final Key? noteKey;

  /// Space above, for every group after the first.
  final bool topGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: WpColors.textMuted,
    );
    return Padding(
      padding: EdgeInsets.only(
        top: topGap ? WpSpacing.md : 0,
        bottom: WpSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: WpColors.textSecondary,
              ),
            ),
          ),
          if (hint case final hint?) ...[
            const SizedBox(height: WpSpacing.xxxs),
            Text(hint, style: muted),
          ],
          if (note case final note?) ...[
            const SizedBox(height: WpSpacing.xxxs),
            Text(note, key: noteKey, style: muted),
          ],
        ],
      ),
    );
  }
}

/// Inset of the star from the tile's end edge.
const double _kStarInset = WpSpacing.xxs;
final double _kStarExtent = WpRowAction.extentFor(dense: true);

/// One grid cell: the language tile and, when [onToggleFavorite] is set, its
/// star at the tile's end, centred on the tile's height. The star is a
/// sibling on top of the tile, not its child, because the tile's Semantics
/// node excludes its children; it carries its own toggle state for screen
/// readers and its own focus stop after the tile.
class _LanguageCell extends StatelessWidget {
  const _LanguageCell({
    super.key,
    required this.option,
    required this.keyPrefix,
    required this.selected,
    required this.onPick,
    required this.favorite,
    required this.favoriteBlocked,
    required this.onToggleFavorite,
  });

  final WpLanguageOption option;

  /// '' in the list of all languages, 'favorites-' in the favorites group,
  /// so both copies of a favorite have their own test ids.
  final String keyPrefix;
  final bool selected;
  final ValueChanged<String> onPick;
  final bool favorite;

  /// True when the list is full and this language is not a favorite.
  final bool favoriteBlocked;

  /// Null hides the star.
  final ValueChanged<String>? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final toggle = onToggleFavorite;
    final tile = _languageTileNode(
      key: ValueKey('stt-language-dialog-${keyPrefix}tile-${option.code}'),
      option: option,
      selected: selected,
      onTap: () => onPick(option.code),
      trailingInset: toggle == null ? 0 : _kStarExtent + 2 * _kStarInset,
    );
    if (toggle == null) return tile;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        tile,
        PositionedDirectional(
          top: 0,
          bottom: 0,
          end: _kStarInset,
          child: Center(
            child: WpFavouriteStar(
              key: ValueKey(
                'stt-language-dialog-${keyPrefix}fav-${option.code}',
              ),
              testId: 'stt-language-dialog-${keyPrefix}fav-${option.code}',
              isFavourite: favorite,
              semanticsLabel: l10n.settingsLanguageFavorite(option.name),
              tooltip: favoriteBlocked
                  ? l10n.settingsLanguageFavoritesLimit(maxFavoriteLanguages)
                  : favorite
                  ? l10n.settingsLanguageFavoriteRemove
                  : l10n.settingsLanguageFavoriteAdd,
              onToggle: favoriteBlocked ? null : () => toggle(option.code),
            ),
          ),
        ),
      ],
    );
  }
}

/// Semantics node for one grid tile: a button named after the language.
/// Wraps the tile at the call site, so the label is set where the tile is used.
Widget _languageTileNode({
  required Key key,
  required WpLanguageOption option,
  required bool selected,
  required VoidCallback onTap,
  double trailingInset = 0,
}) {
  final second = option.secondLine;
  final label = second == null ? option.name : '${option.name}, $second';
  return Semantics(
    label: label,
    key: key,
    button: true,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: _LanguageTile(
      option: option,
      selected: selected,
      onTap: onTap,
      trailingInset: trailingInset,
    ),
  );
}

class _LanguageTile extends StatefulWidget {
  const _LanguageTile({
    required this.option,
    required this.selected,
    required this.onTap,
    this.trailingInset = 0,
  });

  final WpLanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  /// Room kept free at the end for the star laid over the tile.
  final double trailingInset;

  @override
  State<_LanguageTile> createState() => _LanguageTileState();
}

/// Border of every tile; transparent unless selected, so selecting a tile
/// never moves its text.
const double _kTileBorder = 1.5;

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
        borderRadius: WpRadius.borderSm,
        child: Container(
          width: double.infinity,
          padding: EdgeInsetsDirectional.fromSTEB(
            WpSpacing.sm,
            WpSpacing.xs,
            widget.trailingInset > 0 ? widget.trailingInset : WpSpacing.sm,
            WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? WpColors.accentSubtle : WpColors.cardFill,
            borderRadius: WpRadius.borderSm,
            border: Border.all(
              color: selected ? WpColors.accent : Colors.transparent,
              width: _kTileBorder,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Not by colour alone: the chosen tile also has a tick.
                  if (selected) ...[
                    Icon(
                      LucideIcons.check,
                      size: WpIconSize.xs,
                      color: WpColors.accent,
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                  Flexible(
                    child: _LanguageName(
                      name: option.name,
                      style: TextStyle(
                        fontFamily: kWpUiFont,
                        fontFamilyFallback: kWpFontFallback,
                        fontSize: WpTypography.subheading,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WpSpacing.xxxs),
              // Always laid out, empty when there is no endonym, so every
              // tile has two lines and the same height.
              Text(
                option.secondLine ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// A language name in a tile. Names with spaces wrap between words; a
/// single long word (e.g. "Aserbaidschanisch" next to the star) shrinks a
/// little instead of breaking in the middle of the word.
class _LanguageName extends StatelessWidget {
  const _LanguageName({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (name.contains(' ')) return Text(name, style: style);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(name, style: style, maxLines: 1, softWrap: false),
    );
  }
}

/// The current choice under the list: the chosen language, or auto-detect.
/// Kept in view while the list scrolls, so the pick is never off screen.
class _SelectedLine extends StatelessWidget {
  const _SelectedLine({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: WpColors.textMuted,
            ),
          ),
          const SizedBox(width: WpSpacing.xs),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
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
