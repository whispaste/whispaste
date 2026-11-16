import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/l10n/generated/app_localizations.dart';
import 'searchable_list_page.dart';
import 'wp_icon_button.dart';

/// One choice of a [WpSortMenuButton].
class WpSortOption<T> {
  const WpSortOption({
    required this.value,
    required this.id,
    required this.label,
    required this.icon,
  });

  final T value;

  /// Suffix of the option's testID (`<testId>-<id>`). Stable, not translated.
  final String id;
  final String label;
  final IconData icon;
}

/// The one sort control of the list screens: a 44 px icon button that opens
/// the list's action menu with the sort fields, the current one checked, and
/// optionally a "reverse order" entry.
///
/// The button's icon is the current field's icon and its [tooltip] is its
/// accessible name, so it must state the current order (for example
/// "Sortierung: Titel, A–Z"). The menu is the shared list menu, so keyboard
/// and screen-reader behaviour match the overflow menu.
///
/// [reversed], [reverseLabel] and [onReversedChanged] go together: pass all
/// three to offer the direction entry, none of them to omit it.
class WpSortMenuButton<T> extends StatelessWidget {
  const WpSortMenuButton({
    super.key,
    required this.testId,
    required this.tooltip,
    required this.options,
    required this.current,
    required this.onChanged,
    this.reversed,
    this.reverseLabel,
    this.onReversedChanged,
  }) : assert(
         (reversed == null) == (onReversedChanged == null) &&
             (reversed == null) == (reverseLabel == null),
         'reversed, reverseLabel and onReversedChanged go together',
       );

  /// Prefix of the stable testIDs: the button is [testId], its entries
  /// `<testId>-<option id>` and `<testId>-reverse`.
  final String testId;

  /// Accessible name and hover text, including the current order.
  final String tooltip;
  final List<WpSortOption<T>> options;
  final T current;
  final ValueChanged<T> onChanged;

  /// Whether the order is reversed; null when the list has no direction entry.
  final bool? reversed;
  final String? reverseLabel;
  final ValueChanged<bool>? onReversedChanged;

  @override
  Widget build(BuildContext context) {
    final currentOption = options.firstWhere(
      (option) => option.value == current,
      orElse: () => options.first,
    );
    return Builder(
      builder: (buttonContext) => WpIconButton(
        key: ValueKey(testId),
        testId: testId,
        icon: currentOption.icon,
        tooltip: tooltip,
        onPressed: () => showWpListMenu(buttonContext, _actions()),
      ),
    );
  }

  List<WpListMenuAction> _actions() {
    final isReversed = reversed;
    final reverse = onReversedChanged;
    return [
      for (final option in options)
        WpListMenuAction(
          itemKey: ValueKey('$testId-${option.id}'),
          label: option.label,
          icon: option.icon,
          checked: option.value == current,
          onSelected: () => onChanged(option.value),
        ),
      if (isReversed != null && reverse != null && reverseLabel != null)
        WpListMenuAction(
          itemKey: ValueKey('$testId-reverse'),
          label: reverseLabel!,
          icon: LucideIcons.arrowUpDown,
          checked: isReversed,
          onSelected: () => reverse(!isReversed),
        ),
    ];
  }
}

/// The sort order as one phrase for the tooltip and the screen-reader
/// announcement, e.g. "Auslöser, A–Z" or "Zuletzt geändert, neueste zuerst".
/// [fieldLabel] is the list's own name for the field; [isDate] picks the
/// direction words (newest/oldest for dates, A–Z/Z–A for text).
String wpSortOrderLabel(
  L10n l10n, {
  required String fieldLabel,
  required bool isDate,
  required bool reversed,
}) {
  final direction = isDate
      ? (reversed ? l10n.listSortDirectionOldest : l10n.listSortDirectionNewest)
      : (reversed ? l10n.listSortDirectionZA : l10n.listSortDirectionAZ);
  return l10n.listSortOrder(fieldLabel, direction);
}

/// Saves a chosen order, then tells screen-reader users what it is now.
Future<void> saveListSort(
  BuildContext context, {
  required Future<void> Function() save,
  required String Function(L10n l10n) orderLabel,
}) async {
  await save();
  if (!context.mounted) return;
  announce(
    View.of(context),
    orderLabel(L10n.of(context)),
    Directionality.of(context),
  );
}
