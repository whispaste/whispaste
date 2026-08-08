/// Dedicated Flutter entrypoint for the macOS Snippet-Picker render engine
/// (dictation-automations ticket 06).
///
/// Mirrors the floating-button/-overlay shell seam (ADR 0002): the native
/// `SnippetPickerHost`/`SnippetPickerPanel` is a lifecycle-only shell that
/// hosts a **second Flutter engine**, booted with the `snippetPickerMain`
/// entrypoint, whose only job is to paint the searchable snippet list and
/// report the user's pick back over `com.whispaste.snippet_picker_render`.
///
/// Unlike the button/overlay engines (which never take keyboard focus by
/// design), this one *must* — its search field needs real keystrokes — so
/// its root widget is a full `MaterialApp`/`Scaffold`, not the bare
/// `Directionality` the gesture-only surfaces use. The `MaterialApp` carries
/// the real WhisPaste theme (dark/light resolved from the persisted
/// `theme_mode`, mirroring how `resolvePersistedL10n()` resolves copy), so
/// the panel shares the main window's tokens without a Riverpod bridge.
///
/// The visible content is a floating glass panel in the app's Liquid-Glass
/// language — the same no-blur glass recipe the recording overlay uses
/// (top-down sheen, Fresnel inner band, drifting specular streak, top-lit
/// rim; every constant from [OverlayDesignSpec], no constants of its own) —
/// wrapped around a search field, a keyboard-navigable result list (arrows
/// move a single *gliding* highlight, Enter inserts, Escape dismisses — a
/// documented ticket AC) and a slim key-hint footer. The native `NSPanel` is
/// transparent with `hasShadow = true`, so macOS draws the drop shadow
/// around whatever rounded silhouette we paint here.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/colors.dart';
import 'core/theme/overlay_design_spec.dart';
import 'core/theme/persisted_theme.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'services/snippet_picker/snippet_picker_render_channel.dart';
import 'shared_render_engine_helpers.dart' show RenderEngineState;
import 'widgets/wp_search_field.dart';

/// Private channel between the native picker shell and this render engine.
///
/// Distinct from the public `com.whispaste.snippet_picker` channel the main
/// engine uses — the two engines never share a binary messenger, so the
/// names must not collide.
const String _renderChannelName = 'com.whispaste.snippet_picker_render';

/// Boots the Snippet-Picker render engine.
///
/// The actual `@pragma('vm:entry-point') snippetPickerMain` lives in
/// `main.dart` (the root library) because macOS `runWithEntrypoint:`
/// resolves the entrypoint name only against the root library. That thin
/// entrypoint delegates here so the real wiring stays in this cohesive file.
void runSnippetPickerEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[snippet-picker-engine] runSnippetPickerEngine booted');
  runApp(const _SnippetPickerRenderApp());
}

class _SnippetPickerRenderApp extends StatefulWidget {
  const _SnippetPickerRenderApp();

  @override
  State<_SnippetPickerRenderApp> createState() =>
      _SnippetPickerRenderAppState();
}

class _SnippetPickerRenderAppState
    extends
        RenderEngineState<_SnippetPickerRenderApp, SnippetPickerRenderChannel> {
  // English default until the persisted locale resolves (no `Localizations`
  // ancestor exists in a secondary engine — see `RenderEngineState` docs).
  _SnippetPickerRenderAppState()
    : super(lookupL10n(const Locale('en')).snippetsPickerSemanticsLabel);

  List<SnippetPickerRenderItem> _items = const [];
  final _searchController = TextEditingController();

  /// Bumped once per native `setItems` call — the shell sends exactly one
  /// per panel `show()`, and it keeps panel + engine alive across pickers
  /// for the whole app session, so this counter is how the body knows "a
  /// new picker invocation started" and resets its transient search /
  /// highlight / keyboard-focus state (see `_resetForShow`).
  int _showGeneration = 0;

  /// Dark until the persisted preference resolves — matches the app default
  /// (`GeneralSettings.themeMode` defaults to dark).
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _resolveTheme();
  }

  // Resolved once at engine boot; a mid-session theme switch in the main
  // window applies to this panel on the next app start (deliberate
  // simplification — relay it over the channel if that ever matters).
  Future<void> _resolveTheme() async {
    final isDark = await resolvePersistedIsDark();
    if (mounted && isDark != _isDark) setState(() => _isDark = isDark);
  }

  @override
  SnippetPickerRenderChannel createChannel() => SnippetPickerRenderChannel(
    name: _renderChannelName,
    onItems: (items) => setState(() {
      _items = items;
      _showGeneration++;
    }),
  );

  @override
  String labelOf(L10n l10n) => l10n.snippetsPickerSemanticsLabel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Falls back to English until `RenderEngineState` resolves the persisted
    // locale (same pattern as the initial [semanticsLabel]).
    final resolvedL10n = l10n ?? lookupL10n(const Locale('en'));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _isDark ? wpDarkTheme() : wpLightTheme(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Directionality(
          textDirection: Bidi.isRtlLanguage(resolvedL10n.localeName)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Semantics(
            container: true,
            label: semanticsLabel,
            child: _SnippetPickerBody(
              items: _items,
              showGeneration: _showGeneration,
              searchController: _searchController,
              l10n: resolvedL10n,
              onSelect: channel.selectItem,
              onCancel: channel.cancel,
            ),
          ),
        ),
      ),
    );
  }
}

/// The picker panel's visible content: Liquid-Glass surface, capsule search
/// field, a result list with one gliding highlight, and a key-hint footer.
///
/// Motion language (mirrors the recording overlay, all reduced-motion aware
/// via [WpMotion.durationFor] / `MediaQuery.disableAnimations`):
/// - The panel springs in exactly like the overlay capsule
///   ([OverlayDesignSpec.arc]: scale 0.88 → 1.0, easeOutCubic, 300 ms).
/// - The glass chrome's specular streak drifts on the overlay's slow
///   [OverlayDesignSpec.liquidDriftPeriod] cycle — an anchored highlight,
///   never a sweeping shimmer band (ADR 0002).
/// - Arrow keys and mouse hover drive a single highlight capsule that
///   *glides* between rows (Spotlight register) instead of swapping
///   per-tile backgrounds.
class _SnippetPickerBody extends StatefulWidget {
  const _SnippetPickerBody({
    required this.items,
    required this.showGeneration,
    required this.searchController,
    required this.l10n,
    required this.onSelect,
    required this.onCancel,
  });

  final List<SnippetPickerRenderItem> items;

  /// Incremented by the app state once per native `show()` — triggers the
  /// per-invocation reset in [_SnippetPickerBodyState.didUpdateWidget].
  final int showGeneration;

  final TextEditingController searchController;
  final L10n l10n;
  final ValueChanged<String> onSelect;
  final VoidCallback onCancel;

  @override
  State<_SnippetPickerBody> createState() => _SnippetPickerBodyState();
}

class _SnippetPickerBodyState extends State<_SnippetPickerBody>
    with TickerProviderStateMixin {
  /// Fixed tile height — lets the list use `itemExtent` so both the
  /// arrow-key auto-scroll and the gliding highlight capsule can be
  /// positioned with plain offset math.
  ///
  /// Overflow guarantee (fixed after the first live test showed a 6 px
  /// bottom overflow at 56 px): the tile carries **no** vertical margin or
  /// padding any more, and both text lines pin their line height explicitly
  /// (`TextStyle.height`), so the content height is deterministic:
  /// title 13 × 1.3 (16.9) + gap 3 + preview 12 × 1.3 (15.6) = 35.5 px,
  /// centered in the 56 px extent with ~20 px slack. The old layout summed
  /// margins + padding + font-metric line heights past the extent.
  static const double _tileExtent = 56;
  static const double _listPadding = WpSpacing.xxs;

  /// Vertical inset of the gliding highlight capsule inside one tile slot.
  static const double _highlightInset = 2;

  final _scrollController = ScrollController();
  final _searchFocus = FocusNode();
  String _query = '';
  int _highlight = 0;

  /// Overlay-style spring-in (scale 0.88 → 1.0 + fade), one-shot on mount.
  late final AnimationController _appearController = AnimationController(
    vsync: this,
    duration: OverlayDesignSpec.arc.appearDuration,
  );
  late final CurvedAnimation _appear = CurvedAnimation(
    parent: _appearController,
    curve: OverlayDesignSpec.arc.appearCurve,
  );
  late final Animation<double> _appearScale = Tween<double>(
    begin: OverlayDesignSpec.arc.appearScale,
    end: 1,
  ).animate(_appear);

  /// Slow liquid-glass drift phase for the specular streak — the overlay's
  /// own 8 s cycle. Phase 0 renders the exact static frame (reduced motion).
  late final AnimationController _driftController = AnimationController(
    vsync: this,
    duration: OverlayDesignSpec.liquidDriftPeriod,
  );

  /// Live filter across BOTH title and body (ticket AC).
  List<SnippetPickerRenderItem> get _filtered {
    if (_query.isEmpty) return widget.items;
    // ⚡ Bolt: Using precompiled case-insensitive RegExp to avoid allocating
    // new lowercased strings for title and body on every item in the tight loop.
    final searchRegex = RegExp(RegExp.escape(_query), caseSensitive: false);
    return widget.items
        .where(
          (i) => searchRegex.hasMatch(i.title) || searchRegex.hasMatch(i.body),
        )
        .toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: settle instantly on the static frame (appear complete,
    // drift at phase 0) — mirrors how the overlay handles the same flag.
    if (MediaQuery.of(context).disableAnimations) {
      _appearController.value = 1;
      _driftController.stop();
      _driftController.value = 0;
    } else {
      if (!_appearController.isAnimating && !_appearController.isCompleted) {
        _appearController.forward();
      }
      if (!_driftController.isAnimating) _driftController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _SnippetPickerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showGeneration != oldWidget.showGeneration) _resetForShow();
  }

  /// Fresh-picker guarantee on engine reuse: the native shell keeps this
  /// engine (and its widget tree) alive across pickers, so every new
  /// `show()` must clear the previous invocation's query/highlight/scroll
  /// AND re-claim keyboard focus — the search field's `autofocus` fired only
  /// on the very first mount, and an Enter-submit unfocuses the field via
  /// `TextInputAction.done`, so without this the second invocation would
  /// open with dead keyboard input.
  void _resetForShow() {
    widget.searchController.clear();
    setState(() {
      _query = '';
      _highlight = 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _appear.dispose();
    _appearController.dispose();
    _driftController.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _highlight = 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _moveHighlight(int delta) {
    final length = _filtered.length;
    if (length == 0) return;
    setState(() => _highlight = (_highlight + delta).clamp(0, length - 1));
    _scrollHighlightIntoView();
  }

  void _scrollHighlightIntoView() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = _listPadding + _highlight * _tileExtent;
    final bottom = top + _tileExtent;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top - _listPadding;
    } else if (bottom > viewBottom) {
      target = bottom + _listPadding - position.viewportDimension;
    }
    if (target == null) return;
    final offset = target.clamp(0.0, position.maxScrollExtent);
    final duration = WpMotion.durationFor(context, WpMotion.fast);
    if (duration == Duration.zero) {
      _scrollController.jumpTo(offset);
    } else {
      _scrollController.animateTo(
        offset,
        duration: duration,
        curve: WpMotion.defaultCurve,
      );
    }
  }

  void _submit() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      // Dead-end Enter: keep the keyboard in the search field so the user
      // can immediately refine the query.
      _searchFocus.requestFocus();
      return;
    }
    widget.onSelect(filtered[_highlight.clamp(0, filtered.length - 1)].id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = widget.l10n;
    final filtered = _filtered;
    final highlight = filtered.isEmpty
        ? -1
        : _highlight.clamp(0, filtered.length - 1);

    // Single-focus-holder design (live-test 3 fix): the search TextField is
    // the ONLY node in this panel that ever takes keyboard focus. An earlier
    // outer `Focus(autofocus: true)` here raced the field's own autofocus
    // and won (FocusManager applies pending autofocus requests in
    // registration order and discards later ones once the scope has a
    // focused child), so typed characters went nowhere. With the field as
    // sole holder, printable keys land in it by construction, while these
    // Shortcuts — nearer to the focused node than MaterialApp's
    // DefaultTextEditingShortcuts — intercept Arrows/Escape on their way up
    // the focus chain. Enter stays on the TextField's own `onSubmitted`.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveHighlightIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveHighlightIntent(-1),
      },
      child: Actions(
        actions: {
          _CancelIntent: CallbackAction<_CancelIntent>(
            onInvoke: (_) => widget.onCancel(),
          ),
          _MoveHighlightIntent: CallbackAction<_MoveHighlightIntent>(
            onInvoke: (intent) => _moveHighlight(intent.delta),
          ),
        },
        // Overlay-register entrance: anchored under the caret, so the
        // panel grows out of its anchor edge instead of popping from
        // nothing (calm, no overshoot — same curve/scale as the capsule).
        child: ScaleTransition(
          scale: _appearScale,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _appear,
            child: ClipRRect(
              borderRadius: WpRadius.borderXl,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Opaque warm base — the panel floats over arbitrary
                  // desktop content and the list must stay readable, so
                  // (unlike the near-clear capsule) the fill is opaque and
                  // the glass identity is carried by the light layers on
                  // top of it.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? WpColorsDark.warmSurfaceGradient
                          : WpColorsLight.warmSurfaceGradient,
                    ),
                  ),
                  // The overlay's glass light: sheen, Fresnel band,
                  // drifting specular streak, top-lit rim, accent hairline.
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _driftController,
                      builder: (context, _) => CustomPaint(
                        painter: _PanelGlassPainter(
                          phase: _driftController.value,
                          radius: WpRadius.xl,
                          borderColor: isDark
                              ? WpColorsDark.accentBorder20
                              : WpColorsLight.accentBorder20,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          WpSpacing.sm,
                          WpSpacing.sm,
                          WpSpacing.sm,
                          WpSpacing.xs,
                        ),
                        child: _buildSearchField(l10n),
                      ),
                      Expanded(
                        child: _buildListArea(
                          isDark,
                          l10n,
                          filtered,
                          highlight,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WpSpacing.md,
                        ),
                        child: _hairline(isDark),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WpSpacing.md,
                          vertical: WpSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            _KeyHint(
                              isDark: isDark,
                              keyLabel: '↩',
                              label: l10n.snippetsPickerInsertAction,
                            ),
                            const SizedBox(width: WpSpacing.md),
                            _KeyHint(
                              isDark: isDark,
                              keyLabel: 'esc',
                              label: l10n.actionCancel,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Capsule search field — a soft inset glass pill (overlay silhouette DNA)
  /// instead of the main window's rectangular input. The border eases to the
  /// accent tint while focused (continuous, no hard swap).
  Widget _buildSearchField(L10n l10n) {
    return WpSearchField(
      controller: widget.searchController,
      focusNode: _searchFocus,
      hintText: l10n.snippetsSearch,
      variant: WpSearchFieldVariant.capsule,
      // Sole autofocus in the panel (see the build-method comment) —
      // reused-engine re-shows are covered by `_resetForShow` instead,
      // since autofocus only fires on the first mount.
      autofocus: true,
      onChanged: _onQueryChanged,
      onSubmitted: (_) => _submit(),
    );
  }

  /// The list viewport: empty states, or the snippet list with ONE gliding
  /// highlight capsule underneath transparent tiles. The capsule's position
  /// is `listPadding + index × extent − scrollOffset`, eased between rows —
  /// mouse hover and arrow keys retarget the same glide.
  Widget _buildListArea(
    bool isDark,
    L10n l10n,
    List<SnippetPickerRenderItem> filtered,
    int highlight,
  ) {
    if (widget.items.isEmpty) {
      return _EmptyState(
        isDark: isDark,
        icon: LucideIcons.notebookText,
        title: l10n.snippetsEmpty,
      );
    }
    if (filtered.isEmpty) {
      return _EmptyState(
        isDark: isDark,
        icon: LucideIcons.searchX,
        title: l10n.snippetsNoMatches,
        hint: l10n.snippetsNoMatchesHint,
      );
    }
    return ClipRect(
      child: Stack(
        children: [
          if (highlight >= 0)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: highlight.toDouble()),
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: Curves.easeOutCubic,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? WpColorsDark.accentActiveFill
                      : WpColorsLight.accentActiveFill,
                  borderRadius: WpRadius.borderMd,
                  border: Border.all(
                    color: isDark
                        ? WpColorsDark.accentBorder20
                        : WpColorsLight.accentBorder20,
                  ),
                ),
              ),
              builder: (context, animIndex, capsule) => AnimatedBuilder(
                animation: _scrollController,
                builder: (context, _) {
                  final offset = _scrollController.hasClients
                      ? _scrollController.offset
                      : 0.0;
                  return Positioned(
                    left: WpSpacing.xs,
                    right: WpSpacing.xs,
                    top:
                        _listPadding +
                        animIndex * _tileExtent -
                        offset +
                        _highlightInset,
                    height: _tileExtent - 2 * _highlightInset,
                    child: capsule!,
                  );
                },
              ),
            ),
          ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: _listPadding),
            itemExtent: _tileExtent,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final item = filtered[index];
              // False positive at the call site: _PickerTile's own build
              // wraps everything in Semantics(button: true, label:
              // item.title), so the row has an accessible name/role (WCAG
              // 4.1.2 satisfied inside the widget, invisible to the
              // call-site heuristic).
              // loam-ignore: a11y-interactive-semantics – Semantics(label) lives inside _PickerTile
              return _PickerTile(
                item: item,
                isDark: isDark,
                highlighted: index == highlight,
                onHover: () => setState(() => _highlight = index),
                onTap: () => widget.onSelect(item.id),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hairline(bool isDark) => Container(
    height: 1,
    color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
  );
}

/// One snippet row: a soft accent icon chip, title + single-line body
/// preview, and a return-key affordance fading in while highlighted. The
/// tile itself is transparent — the shared gliding highlight capsule in
/// [_SnippetPickerBodyState._buildListArea] paints the selection.
///
/// Layout is deterministic on purpose (see `_tileExtent` docs): no vertical
/// margin/padding, explicit `TextStyle.height` on both lines, content height
/// 35.5 px centered inside the 56 px slot — cannot overflow.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.item,
    required this.isDark,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final SnippetPickerRenderItem item;
  final bool isDark;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  /// Explicit line-height multiplier — pins both text lines to a known
  /// height (fontSize × 1.3) so the tile's total height is arithmetic, not
  /// font-metric dependent (the root cause of the live-test 6 px overflow).
  static const double _lineHeight = 1.3;

  /// Single-line preview of the body — newlines and runs of whitespace
  /// collapse to single spaces so the ellipsis works on one visual line
  /// (same treatment as the main window's snippet tile).
  String get _bodyPreview => item.body.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return Semantics(
      button: true,
      label: item.title,
      child: MouseRegion(
        onEnter: (_) => onHover(),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // The tile is visually transparent (the gliding capsule paints the
          // selection), so opaque hit-testing keeps the full row tappable.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            // xs aligns with the highlight capsule's inset, sm is the
            // content inset inside it.
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs + WpSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDark
                        ? WpColorsDark.accentChipFill
                        : WpColorsLight.accentChipFill,
                    borderRadius: WpRadius.borderSm,
                  ),
                  child: Icon(
                    LucideIcons.notebookText,
                    size: WpIconSize.sm,
                    color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color: isDark
                              ? WpColorsDark.textPrimary
                              : WpColorsLight.textPrimary,
                          fontSize: WpTypography.body,
                          fontWeight: FontWeight.w500,
                          height: _lineHeight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _bodyPreview,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: WpTypography.small,
                          height: _lineHeight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                // Reserved (not conditional) so the text column never
                // reflows when the highlight arrives; the affordance fades
                // in continuously instead of popping.
                AnimatedOpacity(
                  opacity: highlighted ? 1 : 0,
                  duration: WpMotion.durationFor(context, WpMotion.fast),
                  curve: WpMotion.defaultCurve,
                  child: Icon(
                    LucideIcons.cornerDownLeft,
                    size: WpIconSize.xs,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the recording overlay's glass light onto the picker's rounded-rect
/// silhouette — the panel-shaped sibling of `OverlayPainter._drawGlassSheen`.
///
/// Every alpha, stop, width and drift bound comes from [OverlayDesignSpec];
/// this class adds no design constants of its own. Differences from the
/// capsule, both deliberate:
/// - The base fill underneath is opaque (readability of a text list over an
///   arbitrary desktop), so the recipe drops the near-clear fill and keeps
///   only the light layers that carry the glass identity.
/// - The top sheen is compressed into the upper part of the tall panel
///   (shader rect ≈ top 45 %) — mapped over the full 420 px it would read as
///   a milky wash, not as light on glass.
///
/// Like the overlay, the chrome is strictly state-neutral white light plus
/// the fixed accent hairline; [phase] 0 renders the exact static frame.
class _PanelGlassPainter extends CustomPainter {
  const _PanelGlassPainter({
    required this.phase,
    required this.radius,
    required this.borderColor,
  });

  /// Liquid-glass drift phase (`[0, 1)` loop) — see
  /// [OverlayDesignSpec.liquidDriftPeriod].
  final double phase;

  /// Panel corner radius.
  final double radius;

  /// Theme-resolved accent hairline (mirrors the capsule border).
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    // Edge strokes sit half a pixel inside so the ClipRRect around the panel
    // doesn't shave their outer half.
    final edge = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius - 0.5),
    );

    final wave = math.sin(2 * math.pi * phase);
    final breathe = math.sin(4 * math.pi * phase);
    final drift = wave * OverlayDesignSpec.liquidSpecularDriftPx;

    // 1) Top-down sheen — light on curved glass, pulled off the rounded
    //    corners and compressed into the panel's upper region; follows the
    //    specular drift at half parallax (depth cue).
    const sheen = OverlayDesignSpec.glassSheenOpacity;
    final capInset = radius * OverlayDesignSpec.glassSheenCapInsetFactor;
    final sheenRect = Rect.fromLTRB(
      rect.left + capInset,
      rect.top,
      rect.right - capInset,
      rect.top + size.height * 0.45,
    ).shift(Offset(drift * OverlayDesignSpec.liquidSheenParallaxFactor, 0));
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: sheen),
            const Color(0xFFFFFFFF).withValues(alpha: sheen * 0.35),
            const Color(0x00FFFFFF),
          ],
          stops: OverlayDesignSpec.glassSheenStops,
        ).createShader(sheenRect),
    );
    // 2) Hair-thin dark inner shade above the bottom light — the "mass" of
    //    the glass slab.
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00000000),
            const Color(
              0xFF000000,
            ).withValues(alpha: OverlayDesignSpec.glassInnerShadeOpacity),
          ],
          stops: OverlayDesignSpec.glassInnerShadeStops,
        ).createShader(rect),
    );
    // 3) Faint bottom counter-sheen — light catching the lower glass rim.
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(
              alpha: sheen * OverlayDesignSpec.glassBottomSheenFactor,
            ),
          ],
          stops: OverlayDesignSpec.glassBottomSheenStops,
        ).createShader(rect),
    );
    // 4) Soft inner Fresnel band just inside the rim — the refracting
    //    thickness of the slab, fading downward.
    canvas.drawRRect(
      edge.deflate(OverlayDesignSpec.glassInnerRimInset),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = OverlayDesignSpec.glassInnerRimWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(
              0xFFFFFFFF,
            ).withValues(alpha: OverlayDesignSpec.glassInnerRimOpacity),
            const Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );
    // 5) Crisp specular streak along the top edge — the signature drifting
    //    reflection, with the dark under-halo that guarantees local contrast
    //    over light fills (the overlay's measured fix).
    final specularHalf =
        (size.width * OverlayDesignSpec.glassSpecularWidthFactor) /
        2 *
        (1 + OverlayDesignSpec.liquidSpecularBreatheFactor * breathe);
    final specularY = rect.top + OverlayDesignSpec.glassSpecularInsetTop;
    final specularCx = rect.center.dx + drift;
    canvas.drawLine(
      Offset(
        specularCx - specularHalf,
        specularY + OverlayDesignSpec.glassSpecularHaloOffsetY,
      ),
      Offset(
        specularCx + specularHalf,
        specularY + OverlayDesignSpec.glassSpecularHaloOffsetY,
      ),
      Paint()
        ..color = OverlayDesignSpec.glyphShadowColor.withValues(
          alpha: OverlayDesignSpec.glassSpecularHaloOpacity,
        )
        ..strokeWidth = OverlayDesignSpec.glassSpecularHaloStrokeWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.glassSpecularHaloBlurSigma,
        ),
    );
    canvas.drawLine(
      Offset(specularCx - specularHalf, specularY),
      Offset(specularCx + specularHalf, specularY),
      Paint()
        ..strokeWidth = OverlayDesignSpec.glassSpecularStrokeWidth
        ..strokeCap = StrokeCap.round
        ..shader =
            LinearGradient(
              colors: [
                const Color(0x00FFFFFF),
                const Color(0xFFFFFFFF).withValues(
                  alpha:
                      (OverlayDesignSpec.glassSpecularOpacity *
                              (1 +
                                  OverlayDesignSpec
                                          .liquidSpecularBrightBreatheFactor *
                                      breathe))
                          .clamp(0.0, 1.0),
                ),
                const Color(0x00FFFFFF),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(
              Rect.fromLTWH(
                specularCx - specularHalf,
                specularY - 1,
                specularHalf * 2,
                2,
              ),
            ),
    );
    // 6) 1 px outer rim, lit from above and breathing with the drift cycle —
    //    a uniform outline would read as a stroke, not as edge light.
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(
              alpha:
                  (OverlayDesignSpec.glassRimTopOpacity *
                          (1 +
                              OverlayDesignSpec.liquidRimBreatheFactor *
                                  breathe))
                      .clamp(0.0, 1.0),
            ),
            const Color(
              0xFFFFFFFF,
            ).withValues(alpha: OverlayDesignSpec.glassRimBottomOpacity),
          ],
        ).createShader(rect),
    );
    // 7) Fixed accent hairline — the panel's sibling of the capsule border,
    //    drawn last like the overlay's `_drawBorder`.
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _PanelGlassPainter old) =>
      old.phase != phase ||
      old.radius != radius ||
      old.borderColor != borderColor;
}

/// Compact empty-state treatment for the panel (no snippets relayed, or an
/// active search without matches) — a small sibling of the main window's
/// `WpEmptyState`, sized for a 360-pt floating surface.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isDark,
    required this.icon,
    required this.title,
    this.hint,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WpSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: WpIconSize.xl, color: textMuted),
            const SizedBox(height: WpSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hint case final hint?) ...[
              const SizedBox(height: WpSpacing.xxs),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.small,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Footer affordance: a small key-cap chip plus a muted action label.
class _KeyHint extends StatelessWidget {
  const _KeyHint({
    required this.isDark,
    required this.keyLabel,
    required this.label,
  });

  final bool isDark;
  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: isDark
                ? WpColorsDark.surfaceMutedFill
                : WpColorsLight.surfaceMutedFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark
                  ? WpColorsDark.borderSubtle
                  : WpColorsLight.borderSubtle,
            ),
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: isDark
                  ? WpColorsDark.textSecondary
                  : WpColorsLight.textSecondary,
              fontSize: WpTypography.micro,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          label,
          style: TextStyle(color: textMuted, fontSize: WpTypography.caption),
        ),
      ],
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _MoveHighlightIntent extends Intent {
  const _MoveHighlightIntent(this.delta);

  final int delta;
}
