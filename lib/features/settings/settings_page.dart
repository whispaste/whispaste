import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';
import 'search/settings_search_provider.dart';
import 'sections/cloud_advanced_section.dart' show AdvancedSection;
import 'sections/feedback_section.dart';
import 'sections/history_section.dart';
import 'sections/interface_section.dart';
import 'sections/overlay_button_section.dart';
import 'sections/recording_sections.dart';
import 'sections/stt_section.dart';
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
    'advanced': GlobalKey(),
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
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    Widget sectionWithHighlight(String sectionKey, Widget child) {
      final isHighlighted = highlightTarget == sectionKey;
      final accentColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isHighlighted
            ? BoxDecoration(
                borderRadius: WpRadius.borderMd,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.55),
                  width: 2,
                ),
              )
            : const BoxDecoration(),
        child: child,
      );
    }

    // Ordered list of (sectionKey, widget-builder) pairs.
    final allSections = <(String, Widget Function())>[
      (
        'interface',
        () => sectionWithHighlight(
          'interface',
          InterfaceSection(key: _sectionKeys['interface']),
        ),
      ),
      (
        'stt',
        () => sectionWithHighlight(
          'stt',
          SpeechRecognitionSection(key: _sectionKeys['stt']),
        ),
      ),
      (
        'audio',
        () => sectionWithHighlight(
          'audio',
          AudioSection(key: _sectionKeys['audio']),
        ),
      ),
      (
        'afterTranscription',
        () => sectionWithHighlight(
          'afterTranscription',
          AfterTranscriptionSection(key: _sectionKeys['afterTranscription']),
        ),
      ),
      (
        'overlay',
        () => sectionWithHighlight(
          'overlay',
          OverlaySection(key: _sectionKeys['overlay']),
        ),
      ),
      (
        'floatingButton',
        () => sectionWithHighlight(
          'floatingButton',
          FloatingButtonSection(key: _sectionKeys['floatingButton']),
        ),
      ),
      (
        'hotkey',
        () => sectionWithHighlight(
          'hotkey',
          KeyboardShortcutSection(key: _sectionKeys['hotkey']),
        ),
      ),
      (
        'sound',
        () => sectionWithHighlight(
          'sound',
          SoundFeedbackSection(key: _sectionKeys['sound']),
        ),
      ),
      (
        'recordingSafety',
        () => sectionWithHighlight(
          'recordingSafety',
          RecordingSafetySection(key: _sectionKeys['recordingSafety']),
        ),
      ),
      (
        'history',
        () => sectionWithHighlight(
          'history',
          HistorySection(key: _sectionKeys['history']),
        ),
      ),
      (
        'advanced',
        () => sectionWithHighlight(
          'advanced',
          AdvancedSection(key: _sectionKeys['advanced']),
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
      );
    } else {
      // Build sections with dividers only between visible neighbours.
      final children = <Widget>[];
      for (var i = 0; i < visibleSections.length; i++) {
        children.add(visibleSections[i].$2());
        if (i < visibleSections.length - 1) {
          children.add(settingsSectionDivider(context));
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
        child: Column(
          children: [
            // ── Sticky search field (stays visible while scrolling) ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                WpSpacing.sm,
                WpSpacing.xl,
                0,
              ),
              child: SettingsSearchField(focusNode: _searchFocusNode),
            ),

            // ── Scrollable settings content ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  WpSpacing.xl,
                  WpSpacing.sm,
                  WpSpacing.xl,
                  WpSpacing.xl,
                ),
                child: scrollContent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
