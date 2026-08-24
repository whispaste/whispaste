/// Feature spotlight watcher and dialog —
/// `.scratch/feature-spotlight/issues/01-spotlight-mechanism.md`.
///
/// [WpFeatureSpotlightWatcher] listens for the right moment to surface a
/// compact, dismissable hint bundling every pending
/// [FeatureSpotlightEntry] into a single showing, newest first. Mirrors
/// `store_thank_you_dialog.dart`'s watcher/dialog shape closely — the
/// two-second show delay that one uses is deliberately not needed here: the
/// app's startup sequencing (`app.dart`'s `_runStartupPermissionFlows`)
/// already guarantees the check runs at the right point relative to an
/// onboarding revision run, so there is no equivalent race to buy time
/// against.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/config/settings_provider.dart';
import '../core/feature_spotlight/feature_spotlight.dart';
import '../core/feature_spotlight/feature_spotlight_notifier.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/onboarding/onboarding_surface.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';

/// Opens [url] in the system browser, silently doing nothing when the
/// platform can't handle it. Same two-line shape as `about_page.dart`'s and
/// `store_thank_you_dialog.dart`'s own private copies — this app has no
/// shared helper for it, each URL-launching surface keeps its own.
Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Opens the feature spotlight dialog on demand, outside the normal
/// once-per-update trigger — e.g. Settings' "Review the new features" row.
/// Shows every entry in [entries] regardless of its seen state and, unlike
/// [WpFeatureSpotlightWatcher]'s automatic showing, never writes to
/// `seenFeatureSpotlightIds`: this is a deliberate "let me see it again",
/// not a fresh unlock, so closing it (button or barrier tap) just pops.
///
/// Wp naming — no `showWp*` infix: this is a call site of the existing
/// `_FeatureSpotlightDialog` component (the same one
/// [WpFeatureSpotlightWatcher] shows automatically), not a component of its
/// own. See `_documentedExceptions` in `wp_prefix_consistency_test.dart`.
Future<void> showFeatureSpotlightPreview(
  BuildContext context,
  List<FeatureSpotlightEntry> entries,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
    pageBuilder: (_, p1, p2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, p1, p2) {
      final opacity = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: opacity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: wpDialogBarrierColor())),
            _FeatureSpotlightDialog(
              animation: animation,
              entries: entries,
              onDismiss: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Watcher (public entry point)
// ---------------------------------------------------------------------------

/// Listens for the moment to show the feature spotlight hint.
///
/// Triggers [FeatureSpotlightNotifier.checkAndMaybeShow] once onboarding is
/// done — either already completed when this widget mounts (returning
/// users), or the instant [AppSettings.onboarding.onboardingCompleted] flips
/// to `true` in the current session (first-run users).
///
/// Place this widget anywhere above the content layer (e.g., wrapping
/// [WpServiceBootstrap]). It renders no visible UI of its own.
class WpFeatureSpotlightWatcher extends ConsumerStatefulWidget {
  const WpFeatureSpotlightWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpFeatureSpotlightWatcher> createState() =>
      _WpFeatureSpotlightWatcherState();
}

class _WpFeatureSpotlightWatcherState
    extends ConsumerState<WpFeatureSpotlightWatcher> {
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    // Check on first mount — handles returning users whose onboarding was
    // already completed in a previous session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onboarded =
          ref.read(settingsProvider).value?.onboarding.onboardingCompleted ??
          false;
      _triggerCheck(onboarded);
    });
  }

  Future<void> _triggerCheck(bool onboardingCompleted) async {
    await ref
        .read(featureSpotlightProvider.notifier)
        .checkAndMaybeShow(onboardingCompleted: onboardingCompleted);
  }

  void _maybeShow(FeatureSpotlightState state, BuildContext context) {
    if (!state.shouldShow || _dialogShowing) return;
    // Re-ask the two halves of the gate that can flip between check time and
    // this listener firing — a manual review opening from Settings, or an
    // onboarding revision run starting — closes that window. Same reasoning
    // as WpStoreThankYouWatcher's show-time re-check.
    if (ref.read(onboardingManuallyOpenProvider) ||
        ref.read(onboardingRevisionRunProvider)) {
      return;
    }
    _dialogShowing = true;
    _showDialog(context, state.pending);
  }

  Future<void> _showDialog(
    BuildContext context,
    List<FeatureSpotlightEntry> entries,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
      pageBuilder: (_, p1, p2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, p1, p2) {
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: opacity,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: wpDialogBarrierColor())),
              _FeatureSpotlightDialog(
                animation: animation,
                entries: entries,
                onDismiss: () async {
                  Navigator.of(ctx).pop();
                  await _markDismissed();
                },
              ),
            ],
          ),
        );
      },
    );
    // Safety net: ensure the ids are persisted even when the dialog is
    // closed via barrier tap (no explicit button was pressed).
    await _markDismissed();
    _dialogShowing = false;
  }

  Future<void> _markDismissed() =>
      ref.read(featureSpotlightProvider.notifier).dismiss();

  @override
  Widget build(BuildContext context) {
    // Watch for onboarding completion during the current session (first-run).
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final wasCompleted = prev?.value?.onboarding.onboardingCompleted ?? false;
      final isCompleted = next.value?.onboarding.onboardingCompleted ?? false;
      if (!wasCompleted && isCompleted) {
        _triggerCheck(true);
      }
    });

    // Watch for the show signal emitted by the notifier.
    ref.listen<FeatureSpotlightState>(featureSpotlightProvider, (_, next) {
      _maybeShow(next, context);
    });

    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Scrollable entry list with a visible "there's more" affordance
// ---------------------------------------------------------------------------

/// Wraps [child] in a scrollable area with a scrollbar and top/bottom edge
/// fades, both shown only while there is more content in that direction.
///
/// A plain height-clipped `SingleChildScrollView` gives no visual signal
/// that scrolling is even possible — on a short screen the entry list just
/// looks hard-cut at the card's bottom edge (live-tested: with several
/// pending entries the list can be taller than the whole card budget). The
/// fade colour matches [WpColors.floatingSurface] (the card's own fill), so
/// it reads as the content dissolving into the card rather than a distinct
/// overlay box.
class _FadingScrollArea extends StatefulWidget {
  const _FadingScrollArea({required this.child});

  final Widget child;

  @override
  State<_FadingScrollArea> createState() => _FadingScrollAreaState();
}

class _FadingScrollAreaState extends State<_FadingScrollArea> {
  final _controller = ScrollController();
  bool _showTopFade = false;
  bool _showBottomFade = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFades);
    // The controller has no metrics until after the first layout, so the
    // "already scrollable on open" case (several pending entries) needs a
    // post-frame check in addition to the listener.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  void _updateFades() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final showTop = position.pixels > 0;
    final showBottom = position.pixels < position.maxScrollExtent;
    if (showTop != _showTopFade || showBottom != _showBottomFade) {
      setState(() {
        _showTopFade = showTop;
        _showBottomFade = showBottom;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateFades);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tied to the same "more content that way" signal as the fades, rather
    // than always-on: with few entries the list already fits, and a
    // full-height thumb with nothing to scroll to would just be clutter.
    final scrollable = _showTopFade || _showBottomFade;
    return Stack(
      children: [
        Scrollbar(
          controller: _controller,
          thumbVisibility: scrollable,
          child: SingleChildScrollView(
            controller: _controller,
            child: widget.child,
          ),
        ),
        _edgeFade(atTop: true, visible: _showTopFade),
        _edgeFade(atTop: false, visible: _showBottomFade),
      ],
    );
  }

  Widget _edgeFade({required bool atTop, required bool visible}) {
    return Positioned(
      top: atTop ? 0 : null,
      bottom: atTop ? null : 0,
      left: 0,
      right: 0,
      height: WpSpacing.xl,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: WpMotion.durationFor(context, WpMotion.fast),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
                end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  WpColors.floatingSurface,
                  WpColors.floatingSurface.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog widget (package-private)
// ---------------------------------------------------------------------------

class _FeatureSpotlightDialog extends StatelessWidget {
  const _FeatureSpotlightDialog({
    required this.animation,
    required this.entries,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final List<FeatureSpotlightEntry> entries;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    // Bounds the dialog to the viewport regardless of how many entries are
    // pending or how short the screen is — a fixed-size laptop lid or a
    // small external display leaves far less vertical room than the 380 dp
    // width alone accounts for, and the entry list grows with every future
    // feature announcement. Margin mirrors the barrier's own breathing room
    // (`WpSpacing.lg` on both edges) rather than a fraction of the screen,
    // so it stays predictable at any height instead of shrinking the dialog
    // on an otherwise-roomy screen.
    final maxDialogHeight =
        MediaQuery.sizeOf(context).height - WpSpacing.lg * 2;

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            constraints: BoxConstraints(
              maxWidth: 380,
              maxHeight: maxDialogHeight,
            ),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              // Card material, pre-composited: the dialog floats over the
              // 92 %-opaque barrier, so it takes [WpColors.floatingSurface]
              // with the tinted [WpColors.cardEdgeHighlight] rim — the same
              // surface `_WpDialogSurface` (dialog.dart) gives every other
              // dialog. Raw [WpColors.surfaceElevated] under a neutral white
              // hairline is precisely the "still reading as raw
              // surfaceElevated" failure floatingSurface's own doc names.
              color: WpColors.floatingSurface,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: WpColors.cardEdgeHighlight),
              boxShadow: WpShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.featureSpotlightHeading,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.md),
                // The dismiss button below stays pinned outside the scroll
                // area — it must stay reachable even when the entry list
                // itself doesn't fit, which `Flexible` alone can't guarantee
                // (it still won't scroll past its child's own natural size).
                Flexible(
                  child: _FadingScrollArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in entries) ...[
                          if (entry.image != null) ...[
                            ClipRRect(
                              borderRadius: WpRadius.borderMd,
                              child: AspectRatio(
                                // Matches the 340×212 capture convention in
                                // `assets/feature_spotlight/README.md` — the
                                // ratio is what matters (BoxFit.cover), not
                                // the exact pixel count.
                                aspectRatio: 340 / 212,
                                child: Image.asset(
                                  entry.image!,
                                  fit: BoxFit.cover,
                                  // The captures are dark-navy app UI, close
                                  // in tone to the card itself — a hairline
                                  // makes each read as a framed window into
                                  // the app instead of a bitmap dissolving
                                  // into the surface. Painted via
                                  // frameBuilder, not around the ClipRRect,
                                  // so a missing asset degrades borderless
                                  // (no empty outlined box), keeping the
                                  // errorBuilder contract below intact.
                                  frameBuilder:
                                      (
                                        context,
                                        child,
                                        frame,
                                        wasSynchronouslyLoaded,
                                      ) => DecoratedBox(
                                        position: DecorationPosition.foreground,
                                        decoration: BoxDecoration(
                                          borderRadius: WpRadius.borderMd,
                                          border: Border.all(
                                            color: WpColors.borderSubtle,
                                          ),
                                        ),
                                        child: child,
                                      ),
                                  // Purely illustrative — the title/description
                                  // right below already carry the entry's
                                  // actual content, so a screen reader should
                                  // skip this rather than announce a redundant
                                  // fragment.
                                  excludeFromSemantics: true,
                                  // Degrades to the pre-image, text-only
                                  // layout rather than a broken-image icon —
                                  // [image] is documented as optional per
                                  // entry, so a missing asset should read the
                                  // same as one that was never declared.
                                  // Unlike the onboarding beat panel's
                                  // placeholder (`welcome_step.dart`), there
                                  // is no fixed-size slot to fill here.
                                  errorBuilder: (context, error, stackTrace) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            const SizedBox(height: WpSpacing.xs),
                          ],
                          Text(
                            entry.title(l10n),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: WpSpacing.xs),
                          Text(
                            entry.description(l10n),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: WpColors.textSecondary,
                            ),
                          ),
                          // The break between two features has to clearly
                          // beat the air inside one (xs, 8 dp) — at md (16)
                          // the entries ran together as one block. Spacing,
                          // not a hairline: same reasoning as the nav rail's
                          // group break (WpNavRail.groupBreakHeight).
                          if (entry != entries.last)
                            const SizedBox(height: WpSpacing.xl),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: WpSpacing.lg),
                WpButton(
                  label: l10n.featureSpotlightDismiss,
                  variant: WpButtonVariant.primary,
                  autofocus: true,
                  onPressed: onDismiss,
                ),
                const SizedBox(height: WpSpacing.xs),
                // Secondary, non-dismissing affordance — an external link,
                // not a decision about this dialog, so it neither closes it
                // nor competes with the primary CTA above (ghost/neutral,
                // same treatment `store_thank_you_dialog.dart` gives its own
                // secondary action).
                WpButton(
                  label: l10n.featureSpotlightChangelogLink,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  icon: LucideIcons.sparkles,
                  onPressed: () => _launchUrl(kChangelogUrl),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
