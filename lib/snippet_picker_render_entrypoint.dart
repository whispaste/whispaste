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
/// the real WhisPaste theme for the persisted appearance (AR-21, read from the
/// appearance mirror the same way `resolvePersistedL10n()` reads the locale),
/// so the panel shares the main window's tokens without a Riverpod bridge.
///
/// The visible content is a flat floating panel: one solid surface colour
/// (the same flat language as the overlay pill and button), wrapped around a
/// search field, a keyboard-navigable result list (arrows
/// move a single *gliding* highlight, Enter inserts, Escape dismisses — a
/// documented ticket AC) and a slim key-hint footer. The native `NSPanel` is
/// transparent with `hasShadow = true`, so macOS draws the drop shadow
/// around whatever rounded silhouette we paint here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/colors.dart';
import 'core/theme/overlay_design_spec.dart';
import 'core/theme/persisted_appearance.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'services/snippet_picker/snippet_picker_render_channel.dart';
import 'shared_render_engine_helpers.dart'
    show RenderEngineState, detachFromEmbedderAppLifecycle;
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
  // Root cause of the live "arrow keys don't visibly navigate the picker"
  // bug (verified 2026-08-13 with tagged debug instrumentation; the full log
  // evidence is in the fix commit's message): a bogus
  // `AppLifecycleState.hidden` from the embedder froze this engine on the
  // single frame the native `contentViewController` reattach forces per
  // `show()`, and made `FocusManager` drop the search field's primary focus.
  // See [detachFromEmbedderAppLifecycle] for the mechanism; the matching
  // animation gating lives in [SnippetPickerBody.visible].
  detachFromEmbedderAppLifecycle();
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

  /// The colour set this engine paints with. Re-resolved from the appearance
  /// mirror on every picker show, so a change in Settings reaches an engine
  /// that was booted earlier (AR-21).
  late WpThemeColors _colors;

  /// Lets [createChannel]'s `onSubmit` reach [SnippetPickerBody._submit]
  /// directly — the native shell's Return-key monitor bypasses the search
  /// field's `onSubmitted` entirely (see `SnippetPickerRenderChannel.onSubmit`
  /// doc), so this is the only way Enter reaches the same submit logic.
  final _bodyKey = GlobalKey<_SnippetPickerBodyState>();

  /// Bumped once per native `setItems` call — the shell sends exactly one
  /// per panel `show()`, and it keeps panel + engine alive across pickers
  /// for the whole app session, so this counter is how the body knows "a
  /// new picker invocation started" and resets its transient search /
  /// highlight / keyboard-focus state (see `_resetForShow`).
  int _showGeneration = 0;

  /// Whether the native panel is currently on screen.
  ///
  /// Driven entirely by the shell seam — `setItems` (sent once per native
  /// `show()`) flips it on, `panelHidden` (sent by every native `dismiss()`)
  /// flips it off. This engine is detached from the embedder's app
  /// lifecycle (see [detachFromEmbedderAppLifecycle]), so this flag is the
  /// only truthful visibility signal it has, and [SnippetPickerBody] gates
  /// its entrance animation on it.
  bool _panelVisible = false;

  @override
  void initState() {
    super.initState();
    _colors = _resolveAppearance();
  }

  WpThemeColors _resolveAppearance() => resolvePersistedAppearance(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  SnippetPickerRenderChannel createChannel() => SnippetPickerRenderChannel(
    name: _renderChannelName,
    onItems: (items) => setState(() {
      _items = items;
      _showGeneration++;
      _panelVisible = true;
      _colors = _resolveAppearance();
    }),
    onSubmit: () => _bodyKey.currentState?._submit(),
    onPanelHidden: () => setState(() => _panelVisible = false),
    onMoveHighlight: (delta) => _bodyKey.currentState?._moveHighlight(delta),
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
      theme: wpThemeFor(_colors),
      // [WpSearchField] (the capsule field below) reads `L10n.of(context)`
      // itself rather than taking [resolvedL10n] as a parameter — the shared
      // component was built for the main engine, where `app.dart` always
      // wires these three. Without them, `Localizations.of<L10n>` has no
      // delegate to resolve and `WpSearchField` crashes on its very first
      // build. Pinning `locale` to [resolvedL10n] (rather than leaving it
      // null for device-locale resolution) keeps the ambient lookup in sync
      // with the same value already threaded through as `l10n:` below.
      locale: Locale(resolvedL10n.localeName),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Directionality(
          textDirection: Bidi.isRtlLanguage(resolvedL10n.localeName)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Semantics(
            container: true,
            label: semanticsLabel,
            child: SnippetPickerBody(
              key: _bodyKey,
              items: _items,
              showGeneration: _showGeneration,
              visible: _panelVisible,
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

/// The picker panel's visible content: flat surface, capsule search field,
/// a result list with one gliding highlight, and a key-hint footer.
///
/// Motion language (reduced-motion aware via [WpMotion.durationFor] /
/// `MediaQuery.disableAnimations`):
/// - The panel springs in exactly like the overlay capsule
///   ([OverlayDesignSpec.arc]: scale 0.88 → 1.0, easeOutCubic, 300 ms), then
///   stays static: no endless animation runs once it is on screen.
/// - Arrow keys and mouse hover drive a single highlight capsule that
///   *glides* between rows (Spotlight register) instead of swapping
///   per-tile backgrounds.
/// The picker panel's content widget — split out from the private
/// `_SnippetPickerRenderApp` shell (and marked [visibleForTesting]) purely so
/// widget tests can pump it directly without booting a second Flutter engine
/// or a native `NSPanel`. Not part of the public API otherwise: every other
/// caller is [_SnippetPickerRenderAppState] in this same file.
@visibleForTesting
/// Transparent margin around the picker card, drawn inside the native window.
/// The native shells size the window to the card plus this inset on every
/// side, so the Dart-drawn shadow ([WpShadows.card], blur 14 + offset 4) is
/// never clipped by the window edge and looks the same on macOS, Windows and
/// Linux. Keep in sync with SnippetPickerHost.swift, snippet_picker_host.cpp
/// and snippet_picker_window.h.
const double kSnippetPickerShadowInset = 20;

class SnippetPickerBody extends StatefulWidget {
  const SnippetPickerBody({
    super.key,
    required this.items,
    required this.showGeneration,
    required this.visible,
    required this.searchController,
    required this.l10n,
    required this.onSelect,
    required this.onCancel,
  });

  final List<SnippetPickerRenderItem> items;

  /// Incremented by the app state once per native `show()` — triggers the
  /// per-invocation reset in [_SnippetPickerBodyState.didUpdateWidget].
  final int showGeneration;

  /// Whether the native panel is on screen right now (see
  /// `_SnippetPickerRenderAppState._panelVisible` for the shell seam that
  /// drives it). Gates the entrance animation: this engine is detached from
  /// the embedder's app lifecycle, so frames are never lifecycle-disabled, and
  /// an ordered-out panel must not keep animating for the whole app session.
  final bool visible;

  final TextEditingController searchController;
  final L10n l10n;
  final ValueChanged<String> onSelect;
  final VoidCallback onCancel;

  @override
  State<SnippetPickerBody> createState() => _SnippetPickerBodyState();
}

class _SnippetPickerBodyState extends State<SnippetPickerBody>
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

  /// Live filter across BOTH title and body (ticket AC), ranked by match
  /// relevance rather than left in the original list order: a title match
  /// is a stronger signal of intent than a body-only match, and a title
  /// starting with the query beats one merely containing it — otherwise a
  /// query like "impl" ranks a snippet whose body happens to mention the
  /// word above one titled "Implementierung" (reported by the user, e.g.
  /// "Debugging" outranking "Implementierung" for that query).
  List<SnippetPickerRenderItem> get _filtered {
    if (_query.isEmpty) return widget.items;
    // ⚡ Bolt: Using precompiled case-insensitive RegExp to avoid allocating
    // new lowercased strings for title and body on every item in the tight loop.
    final searchRegex = RegExp(RegExp.escape(_query), caseSensitive: false);
    final lowerQuery = _query.toLowerCase();
    final matches = <(SnippetPickerRenderItem item, int rank)>[];
    for (final item in widget.items) {
      final titleMatch = searchRegex.hasMatch(item.title);
      final bodyMatch = searchRegex.hasMatch(item.body);
      if (!titleMatch && !bodyMatch) continue;
      final rank = titleMatch
          ? (item.title.toLowerCase().startsWith(lowerQuery) ? 0 : 1)
          : 2;
      matches.add((item, rank));
    }
    matches.sort((a, b) => a.$2.compareTo(b.$2));
    return matches.map((m) => m.$1).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant SnippetPickerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showGeneration != oldWidget.showGeneration) {
      // A new show() always bumps the generation (and flips `visible` on in
      // the same update); _resetForShow ends in _syncAnimations itself.
      _resetForShow();
    } else if (widget.visible != oldWidget.visible) {
      // A dismiss only flips `visible` off — stop the entrance animation.
      _syncAnimations();
    }
  }

  /// Runs the entrance animation only while the panel is actually on screen.
  ///
  /// Reduced motion settles instantly on the static frame (appear complete).
  /// Otherwise the entrance runs while [SnippetPickerBody.visible] is true and
  /// is stopped on dismiss: this engine is detached from the embedder's app
  /// lifecycle (see [detachFromEmbedderAppLifecycle]).
  void _syncAnimations() {
    if (MediaQuery.of(context).disableAnimations) {
      _appearController.value = 1;
      return;
    }
    if (!widget.visible) {
      _appearController.stop();
      return;
    }
    if (!_appearController.isAnimating && !_appearController.isCompleted) {
      _appearController.forward();
    }
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
    // Replay the documented spring-in on every show, not only the first
    // mount: the panel is reused across pickers, and before the
    // frame-starvation fix (frames were lifecycle-disabled, so only one
    // forced frame per show ever rendered) a re-show's missing entrance was
    // simply invisible. Reduced motion keeps the instant static frame.
    if (!MediaQuery.of(context).disableAnimations) {
      _appearController.forward(from: 0);
    }
    _syncAnimations();
  }

  @override
  void dispose() {
    _appear.dispose();
    _appearController.dispose();
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
        child: Padding(
          padding: const EdgeInsets.all(kSnippetPickerShadowInset),
          child: ScaleTransition(
            scale: _appearScale,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _appear,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: WpRadius.borderXl,
                  boxShadow: WpShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: WpRadius.borderXl,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // One flat fill, no glass layers: the same flat surface
                      // language as the overlay pill and button. The list must
                      // stay readable over arbitrary desktop content.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: WpColors.surface,
                          border: Border.all(color: WpColors.accentBorder20),
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
                            child: _buildListArea(l10n, filtered, highlight),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.md,
                            ),
                            child: _hairline(),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.md,
                              vertical: WpSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                // The insert hint is a promise about the Enter
                                // key. With no row to insert — no snippets
                                // relayed at all, or a query without matches —
                                // `_submit` deliberately does nothing but
                                // re-focus the field, so the hint would keep
                                // advertising an action that has no effect,
                                // right next to the empty state that just said
                                // there is nothing here. Escape is
                                // unconditional because it always works.
                                if (highlight >= 0) ...[
                                  _KeyHint(
                                    keyLabel: '↩',
                                    label: l10n.snippetsPickerInsertAction,
                                  ),
                                  const SizedBox(width: WpSpacing.md),
                                ],
                                _KeyHint(
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
        ),
      ),
    );
  }

  /// Capsule search field — a rounded pill (overlay silhouette DNA) instead
  /// of the main window's rectangular input. The border eases to the
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
      semanticsLabel: l10n.snippetsSearchFieldLabel,
    );
  }

  /// The list viewport: empty states, or the snippet list with ONE gliding
  /// highlight capsule underneath transparent tiles. The capsule's position
  /// is `listPadding + index × extent − scrollOffset`, eased between rows —
  /// mouse hover and arrow keys retarget the same glide.
  Widget _buildListArea(
    L10n l10n,
    List<SnippetPickerRenderItem> filtered,
    int highlight,
  ) {
    if (widget.items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.notebookText,
        title: l10n.snippetsEmpty,
      );
    }
    if (filtered.isEmpty) {
      return _EmptyState(
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
                  color: WpColors.accentActiveFill,
                  borderRadius: WpRadius.borderMd,
                  border: Border.all(color: WpColors.accentBorder20),
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
              // wraps everything in MergeSemantics + Semantics(button:
              // true), so the row has an accessible name (merged from its
              // own title/preview text) and role — WCAG 4.1.2 satisfied
              // inside the widget, invisible to the call-site heuristic.
              // loam-ignore: a11y-interactive-semantics – Semantics lives inside _PickerTile
              return _PickerTile(
                item: item,
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

  Widget _hairline() => Container(height: 1, color: WpColors.borderSubtle);
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
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final SnippetPickerRenderItem item;
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
    final textMuted = WpColors.textMuted;
    // House idiom for a composed control (`section.dart`,
    // `mic_permission_chip.dart`): MergeSemantics + a *label-less*
    // Semantics. An explicit `label: item.title` here does not replace the
    // subtree's own text, it is prepended to it — the rendered title `Text`
    // still contributes a node, so a screen reader announced the title
    // twice on every row of the picker.
    //
    // `selected: highlighted` is what makes the panel usable without sight:
    // the gliding capsule is the *only* selection cue, and it is not focus
    // (the search field is the sole focus holder by design), so without
    // this flag arrow keys moved a highlight the semantics tree never
    // reported.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: highlighted,
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
                      color: WpColors.accentChipFill,
                      borderRadius: WpRadius.borderSm,
                    ),
                    child: Icon(
                      LucideIcons.notebookText,
                      size: WpIconSize.sm,
                      color: WpColors.accent,
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
                            color: WpColors.textPrimary,
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
      ),
    );
  }
}

/// Compact empty-state treatment for the panel (no snippets relayed, or an
/// active search without matches) — a small sibling of the main window's
/// `WpEmptyState`, sized for a 360-pt floating surface.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final textMuted = WpColors.textMuted;
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
                color: WpColors.textSecondary,
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
  const _KeyHint({required this.keyLabel, required this.label});

  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textMuted = WpColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: WpColors.surfaceMutedFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: WpColors.borderSubtle),
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: WpColors.textSecondary,
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
