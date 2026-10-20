/// The recording dock's row plan (WP-79, ADR 0024): for a dock width and the
/// measured text widths, which controls show their label, their icon and
/// value, only their icon, or move into the Mehr menu, and whether the keycap,
/// the Dictate button and the status shrink. Pure arithmetic, so the collapse
/// order can be tested without a widget tree.
///
/// The row steps down one change at a time and the first step that fits wins:
/// 1. selectors with labels, keycap on;
/// 2. selectors as icon and value, keycap on;
/// 3. the keycap inside the Dictate button goes (the hotkey stays in the
///    Dictate tooltip and in Mehr);
/// 4. each droppable selector in drop-rank order shrinks to its icon;
/// 5. each droppable selector in drop-rank order moves into Mehr;
/// 6. the Dictate button and the status shorten;
/// 7. the Dictate button becomes its icon.
///
/// If even step 7 is too wide, [WpDockRowPlan.fits] is false. The widget then
/// keeps step 7 at its widths and scrolls the row sideways, with a scrollbar,
/// so nothing overflows or is cut off silently.
/// The engine selector never shrinks to an icon and never moves into Mehr.
library;

/// How one selector is drawn in the row.
enum WpDockSelectorForm {
  /// Overline and value, with the chevron.
  labelled,

  /// Icon and value, with the chevron. No overline.
  compact,

  /// The icon alone; the value moves into the tooltip and the semantics.
  iconOnly,

  /// Not in the row: the selector's action is in the Mehr menu.
  inMenu,
}

/// One selector as the row sees it: the measured widths in each form and its
/// drop rank. A null [dropRank] means the selector stays in the row.
final class WpDockSelectorSpec {
  const WpDockSelectorSpec({
    required this.id,
    required this.labelledWidth,
    required this.compactWidth,
    required this.iconWidth,
    this.dropRank,
  });

  /// Stable id; the widget key is `dock-<id>`.
  final String id;

  final double labelledWidth;
  final double compactWidth;

  /// The 48 px hit target of the icon-only form.
  final double iconWidth;

  /// Lower ranks shrink and move first. Null: never shrinks, never moves.
  final int? dropRank;

  bool get droppable => dropRank != null;
}

/// The measured inputs of one row.
final class WpDockRowMetrics {
  const WpDockRowMetrics({
    required this.available,
    required this.dictateFull,
    required this.dictateCompact,
    required this.dictateIcon,
    required this.keycapWidth,
    required this.statusFull,
    required this.statusShort,
    required this.overflowWidth,
    required this.gap,
    required this.allowLabels,
    required this.belowCompactBreakpoint,
    required this.selectors,
  });

  /// The width the row may use: the dock width minus its padding.
  final double available;

  /// Measured widths of the Dictate button in each form.
  final double dictateFull;
  final double dictateCompact;
  final double dictateIcon;

  /// The keycap's width inside the Dictate button, gap included; 0 when there
  /// is no hotkey to show.
  final double keycapWidth;

  /// Reserved widths of the status (the status itself flexes into the rest).
  final double statusFull;
  final double statusShort;

  /// 0 when Mehr has nothing to show.
  final double overflowWidth;

  /// Gap between two neighbouring items.
  final double gap;

  /// False below the labels breakpoint or at a raised text scale: selectors
  /// then start as icon and value.
  final bool allowLabels;

  /// True below the compact breakpoint: every droppable selector starts in
  /// Mehr.
  final bool belowCompactBreakpoint;

  /// Left to right.
  final List<WpDockSelectorSpec> selectors;
}

/// The chosen layout of one row.
final class WpDockRowPlan {
  const WpDockRowPlan({
    required this.forms,
    required this.keycap,
    required this.dictateCompact,
    required this.dictateIcon,
    required this.statusShort,
    required this.belowCompactBreakpoint,
    required this.fits,
  });

  final Map<String, WpDockSelectorForm> forms;
  final bool keycap;
  final bool dictateCompact;
  final bool dictateIcon;
  final bool statusShort;
  final bool belowCompactBreakpoint;

  /// False only when even the last step is wider than the row.
  final bool fits;

  WpDockSelectorForm formOf(String id) {
    final form = forms[id];
    if (form == null) throw ArgumentError.value(id, 'id', 'unknown selector');
    return form;
  }
}

/// One candidate layout. Immutable; each step returns a changed copy.
final class _RowState {
  const _RowState({
    required this.forms,
    required this.keycap,
    required this.dictateCompact,
    required this.dictateIcon,
    required this.statusShort,
  });

  final Map<String, WpDockSelectorForm> forms;
  final bool keycap;
  final bool dictateCompact;
  final bool dictateIcon;
  final bool statusShort;

  _RowState copy({
    Map<String, WpDockSelectorForm>? forms,
    bool? keycap,
    bool? dictateCompact,
    bool? dictateIcon,
    bool? statusShort,
  }) => _RowState(
    forms: forms ?? this.forms,
    keycap: keycap ?? this.keycap,
    dictateCompact: dictateCompact ?? this.dictateCompact,
    dictateIcon: dictateIcon ?? this.dictateIcon,
    statusShort: statusShort ?? this.statusShort,
  );

  _RowState withForm(String id, WpDockSelectorForm form) =>
      copy(forms: {...forms, id: form});

  WpDockRowPlan toPlan(WpDockRowMetrics m, {required bool fits}) =>
      WpDockRowPlan(
        forms: forms,
        keycap: keycap,
        dictateCompact: dictateCompact,
        dictateIcon: dictateIcon,
        statusShort: statusShort,
        belowCompactBreakpoint: m.belowCompactBreakpoint,
        fits: fits,
      );
}

WpDockRowPlan planDockRow(WpDockRowMetrics m) {
  final droppable = m.selectors.where((s) => s.droppable).toList()
    ..sort((a, b) => a.dropRank!.compareTo(b.dropRank!));

  final start = <String, WpDockSelectorForm>{
    for (final s in m.selectors)
      s.id: s.droppable && m.belowCompactBreakpoint
          ? WpDockSelectorForm.inMenu
          : (m.allowLabels
                ? WpDockSelectorForm.labelled
                : WpDockSelectorForm.compact),
  };

  final steps = <_RowState>[];
  var state = _RowState(
    forms: start,
    keycap: m.keycapWidth > 0,
    dictateCompact: false,
    dictateIcon: false,
    statusShort: false,
  );
  if (!m.belowCompactBreakpoint && m.allowLabels) steps.add(state);

  // Every selector that is not in Mehr shows icon and value.
  state = state.copy(
    forms: {
      for (final e in state.forms.entries)
        e.key: e.value == WpDockSelectorForm.labelled
            ? WpDockSelectorForm.compact
            : e.value,
    },
  );
  steps.add(state);

  state = state.copy(keycap: false);
  steps.add(state);

  if (!m.belowCompactBreakpoint) {
    for (final s in droppable) {
      state = state.withForm(s.id, WpDockSelectorForm.iconOnly);
      steps.add(state);
    }
  }
  for (final s in droppable) {
    state = state.withForm(s.id, WpDockSelectorForm.inMenu);
    steps.add(state);
  }

  state = state.copy(dictateCompact: true, statusShort: true);
  steps.add(state);

  state = state.copy(dictateIcon: true);
  steps.add(state);

  for (final step in steps) {
    if (_widthOf(step, m) <= m.available) {
      return step.toPlan(m, fits: true);
    }
  }
  return steps.last.toPlan(m, fits: false);
}

double _widthOf(_RowState state, WpDockRowMetrics m) {
  // The keycap is part of the Dictate button, so it adds to the button's width
  // rather than standing as an item of its own.
  final keycapInside = state.keycap && m.keycapWidth > 0 && !state.dictateIcon;
  final widths = <double>[
    (state.dictateIcon
            ? m.dictateIcon
            : state.dictateCompact
            ? m.dictateCompact
            : m.dictateFull) +
        (keycapInside ? m.keycapWidth : 0),
    state.statusShort ? m.statusShort : m.statusFull,
    if (m.overflowWidth > 0) m.overflowWidth,
  ];
  for (final s in m.selectors) {
    switch (state.forms[s.id]!) {
      case WpDockSelectorForm.labelled:
        widths.add(s.labelledWidth);
      case WpDockSelectorForm.compact:
        widths.add(s.compactWidth);
      case WpDockSelectorForm.iconOnly:
        widths.add(s.iconWidth);
      case WpDockSelectorForm.inMenu:
        break;
    }
  }
  final gaps = widths.length - 1;
  return widths.fold<double>(0, (sum, w) => sum + w) + gaps * m.gap;
}
