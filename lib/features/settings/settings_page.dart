import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import 'search/settings_search_provider.dart';
import 'sections/cloud_advanced_section.dart' show AdvancedSection;
import 'sections/feedback_section.dart';
import 'sections/history_section.dart';
import 'sections/interface_section.dart';
import 'sections/onboarding_review_section.dart';
import 'sections/overlay_button_section.dart';
import 'sections/privacy_section.dart';
import 'sections/recording_sections.dart';
import 'sections/review_support_section.dart';
import 'sections/settings_portability_section.dart';
import 'sections/stt_section.dart';
import 'sections/updates_section.dart';
import 'settings_widgets.dart';
import 'widgets/settings_search_field.dart';

/// Settings page — thin coordinator that composes extracted section widgets.
///
/// Supports deep-linking: when [settingsScrollTargetProvider] contains a
/// section id (e.g. `'stt'`, `'hotkey'`), the page scrolls to that section
/// on mount and clears the target.
///
/// The sticky search field at the top stays visible while scrolling.
/// Selecting a suggestion scrolls to and briefly highlights the target section
/// via [settingsHighlightTargetProvider].
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _searchFocusNode = FocusNode();

  final _sectionKeys = <String, GlobalKey>{
    'interface': GlobalKey(),
    'stt': GlobalKey(),
    'audio': GlobalKey(),
    'afterTranscription': GlobalKey(),
    'overlay': GlobalKey(),
    'floatingButton': GlobalKey(),
    'hotkey': GlobalKey(),
    'sound': GlobalKey(),
    'recordingSafety': GlobalKey(),
    'history': GlobalKey(),
    'settingsPortability': GlobalKey(),
    'advanced': GlobalKey(),
    'updates': GlobalKey(),
    'onboardingReview': GlobalKey(),
    'reviewSupport': GlobalKey(),
    'privacy': GlobalKey(),
  };

  Timer? _highlightClearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTargetIfNeeded();
    });
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _scrollToTargetIfNeeded() {
    final target = ref.read(settingsScrollTargetProvider);
    if (target == null) return;

    ref.read(settingsScrollTargetProvider.notifier).set(null);

    final key = _sectionKeys[target];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: WpMotion.durationFor(
          targetContext,
          const Duration(milliseconds: 300),
        ),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  void _startHighlightClearTimer() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        ref.read(settingsHighlightTargetProvider.notifier).set(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // Watch scroll target — triggers when search field selects a suggestion.
    ref.listen(settingsScrollTargetProvider, (_, target) {
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTargetIfNeeded();
        });
      }
    });

    // Watch highlight target — cleared automatically after 1.5 s.
    ref.listen(settingsHighlightTargetProvider, (_, target) {
      if (target != null) {
        _startHighlightClearTimer();
      }
    });

    final highlightTarget = ref.watch(settingsHighlightTargetProvider);

    // null = show all; non-null Set = show only those sectionKeys.
    final matchSet = ref.watch(settingsSectionMatchSetProvider);

    // Narrow watch on purpose — this page must not rebuild on every unrelated
    // settings change just to decide one section's presence.
    final onboardingCompleted = ref.watch(
      settingsProvider.select(
        (s) => s.value?.onboarding.onboardingCompleted ?? false,
      ),
    );

    /// One settings section, on the app's card material, plus the transient
    /// locator ring a search hit paints over it.
    ///
    /// The card is Ticket 14's half. Before it, the sixteen sections were
    /// sixteen headings and their rows laid straight onto the page ground,
    /// separated by 32 px of nothing — which is a lot of air to spend on a
    /// boundary that air alone has to carry, and it still left the reader
    /// working out by eye where "Audio" ended and "After transcription"
    /// began. The same recipe as `_AboutCard` and the analytics panels: the
    /// translucent [WpColors.cardFill] because these cards sit inside the
    /// content panel rather than on their own ground, a
    /// [WpColors.cardEdgeHighlight] rim, and no shadow (the Depth-Source
    /// Rule, `lib/DESIGN.md`). With the boundary drawn, the gap between two
    /// cards drops to `WpSpacing.lg`, matching About.
    Widget sectionCard(String sectionKey, Widget child) {
      final isHighlighted = highlightTarget == sectionKey;
      // Its own token, deliberately above the tint ladder's 30 % ceiling — the
      // ring has to be caught in peripheral vision and clears itself after
      // 1.5 s, which is the opposite job from a resting outline. See
      // WpColorsDark.accentLocatorRing.
      const ringColor = WpColors.accentLocatorRing;
      return AnimatedContainer(
        duration: WpMotion.durationFor(
          context,
          const Duration(milliseconds: 200),
        ),
        padding: const EdgeInsets.all(WpSpacing.lg),
        // The card's own border lives here, in the background decoration, and
        // is safe there precisely because it never changes: a `Border` in
        // `decoration` is laid out, not just painted, so the container insets
        // its child by the border width — constant cost, no movement.
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderLg,
          border: Border.all(color: WpColors.cardEdgeHighlight),
        ),
        // The *ring*, by contrast, goes in `foregroundDecoration`, never in
        // `decoration`: it is transient (it arrives with a search hit and
        // clears itself 1.5 s later), so laying it out made the whole section
        // jump 2 px inward on arrival and 2 px back on expiry, twice per
        // search. Painted in the foreground it costs zero layout and the
        // section holds still.
        foregroundDecoration: isHighlighted
            ? BoxDecoration(
                borderRadius: WpRadius.borderLg,
                border: Border.all(color: ringColor, width: 2),
              )
            : const BoxDecoration(),
        child: child,
      );
    }

    // Ordered list of (sectionKey, widget-builder) pairs.
    final allSections = <(String, Widget Function())>[
      (
        'interface',
        () => sectionCard(
          'interface',
          InterfaceSection(key: _sectionKeys['interface']),
        ),
      ),
      (
        'stt',
        () => sectionCard(
          'stt',
          SpeechRecognitionSection(key: _sectionKeys['stt']),
        ),
      ),
      (
        'audio',
        () => sectionCard('audio', AudioSection(key: _sectionKeys['audio'])),
      ),
      (
        'afterTranscription',
        () => sectionCard(
          'afterTranscription',
          AfterTranscriptionSection(key: _sectionKeys['afterTranscription']),
        ),
      ),
      (
        'overlay',
        () => sectionCard(
          'overlay',
          OverlaySection(key: _sectionKeys['overlay']),
        ),
      ),
      (
        'floatingButton',
        () => sectionCard(
          'floatingButton',
          FloatingButtonSection(key: _sectionKeys['floatingButton']),
        ),
      ),
      (
        'hotkey',
        () => sectionCard(
          'hotkey',
          KeyboardShortcutSection(key: _sectionKeys['hotkey']),
        ),
      ),
      (
        'sound',
        () => sectionCard(
          'sound',
          SoundFeedbackSection(key: _sectionKeys['sound']),
        ),
      ),
      (
        'recordingSafety',
        () => sectionCard(
          'recordingSafety',
          RecordingSafetySection(key: _sectionKeys['recordingSafety']),
        ),
      ),
      (
        'history',
        () => sectionCard(
          'history',
          HistorySection(key: _sectionKeys['history']),
        ),
      ),
      (
        'settingsPortability',
        () => sectionCard(
          'settingsPortability',
          SettingsPortabilitySection(key: _sectionKeys['settingsPortability']),
        ),
      ),
      (
        'advanced',
        () => sectionCard(
          'advanced',
          AdvancedSection(key: _sectionKeys['advanced']),
        ),
      ),
      (
        'updates',
        () => sectionCard(
          'updates',
          UpdatesSection(key: _sectionKeys['updates']),
        ),
      ),
      // Only for users who already finished the first-run setup: an
      // unfinished one has the flow on screen anyway. Filtered out of the
      // list rather than rendered as an empty box, so the dividers between
      // the surviving sections stay single.
      if (onboardingCompleted)
        (
          'onboardingReview',
          () => sectionCard(
            'onboardingReview',
            OnboardingReviewSection(key: _sectionKeys['onboardingReview']),
          ),
        ),
      (
        'reviewSupport',
        () => sectionCard(
          'reviewSupport',
          ReviewSupportSection(key: _sectionKeys['reviewSupport']),
        ),
      ),
      (
        'privacy',
        () => sectionCard(
          'privacy',
          PrivacySection(key: _sectionKeys['privacy']),
        ),
      ),
    ];

    // Filter to visible sections (matchSet == null means show all).
    final visibleSections = matchSet == null
        ? allSections
        : allSections.where((s) => matchSet.contains(s.$1)).toList();

    // Build scrollable content — either the filtered list or a "no results" state.
    Widget scrollContent;
    if (visibleSections.isEmpty && matchSet != null) {
      // Zero matches → centred empty state.
      scrollContent = WpEmptyState(
        icon: LucideIcons.searchX,
        title: l10n.settingsSearchNoResults,
        hint: l10n.settingsSearchNoResultsHint,
        // Per the WpEmptyState rule the search-empty state offers its main
        // action: get out of the search. The query provider is the single
        // source of truth here — the field mirrors an external reset back
        // into its own controller.
        actionLabel: l10n.actionClearSearch,
        onAction: () => ref.read(settingsSearchQueryProvider.notifier).set(''),
      );
    } else {
      // Build sections with dividers only between visible neighbours.
      final children = <Widget>[];
      for (var i = 0; i < visibleSections.length; i++) {
        children.add(visibleSections[i].$2());
        if (i < visibleSections.length - 1) {
          children.add(settingsSectionBreak);
        }
      }
      scrollContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+F / Cmd+F: focus the settings search field
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          _searchFocusNode.requestFocus();
        },
      },
      // Focus wrapper: autofocus ensures a descendant of CallbackShortcuts
      // has focus when the page loads so that the Ctrl+F / Cmd+F shortcut is
      // reachable via key-event bubbling without stealing interactive focus.
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: Builder(
          builder: (context) {
            // Fills the window width like every other page (The Fill-By-
            // Default Rule) — no cap-width, so Settings stays consistent
            // with History/Analytics/etc. even on very wide windows.
            //
            // The search field rides the shell's sticky header slot, so it
            // stays visible while the sections below scroll.
            //
            // No ground of its own. Settings used to wrap the shell in a flat
            // decorative wash (*The Decorative Color Rule*, retracted
            // 2026-08-11) to read as its own plate; the plate is now the one
            // the whole app stands on, so the page returns the bare shell and
            // lands on `warmSurfaceGradient` like History, Analytics and every
            // other page. A page that paints its own fill over the content
            // plane is the same seam Ticket 06 removed from the nav rail, one
            // layer in.
            return WpPageShell(
              header: SettingsSearchField(focusNode: _searchFocusNode),
              child: scrollContent,
            );
          },
        ),
      ),
    );
  }
}
