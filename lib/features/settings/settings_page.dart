import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import 'sections/cloud_advanced_section.dart' show AdvancedSection;
import 'sections/feedback_section.dart';
import 'sections/gpu_acceleration_section.dart';
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
  final _sectionKeys = <String, GlobalKey>{
    'interface': GlobalKey(),
    'stt': GlobalKey(),
    'gpu': GlobalKey(),
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

    return Column(
      children: [
        // ── Sticky search field (stays visible while scrolling) ───────────
        const Padding(
          padding: EdgeInsets.fromLTRB(
            WpSpacing.xl,
            WpSpacing.sm,
            WpSpacing.xl,
            0,
          ),
          child: SettingsSearchField(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════
                //  GENERAL
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'interface',
                  InterfaceSection(key: _sectionKeys['interface']),
                ),
                settingsSectionDivider(context),

                // ═══════════════════════════════════════════
                //  CORE WORKFLOW
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'stt',
                  SpeechRecognitionSection(key: _sectionKeys['stt']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'gpu',
                  GpuAccelerationSection(key: _sectionKeys['gpu']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'audio',
                  AudioSection(key: _sectionKeys['audio']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'afterTranscription',
                  AfterTranscriptionSection(
                    key: _sectionKeys['afterTranscription'],
                  ),
                ),
                settingsSectionDivider(context),

                // ═══════════════════════════════════════════
                //  FLOATING UI ELEMENTS
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'overlay',
                  OverlaySection(key: _sectionKeys['overlay']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'floatingButton',
                  FloatingButtonSection(key: _sectionKeys['floatingButton']),
                ),
                settingsSectionDivider(context),

                // ═══════════════════════════════════════════
                //  INTERACTION
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'hotkey',
                  KeyboardShortcutSection(key: _sectionKeys['hotkey']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'sound',
                  SoundFeedbackSection(key: _sectionKeys['sound']),
                ),
                settingsSectionDivider(context),

                // ═══════════════════════════════════════════
                //  DATA MANAGEMENT
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'recordingSafety',
                  RecordingSafetySection(key: _sectionKeys['recordingSafety']),
                ),
                settingsSectionDivider(context),
                sectionWithHighlight(
                  'history',
                  HistorySection(key: _sectionKeys['history']),
                ),
                settingsSectionDivider(context),

                // ═══════════════════════════════════════════
                //  TECHNICAL / RARELY CHANGED
                // ═══════════════════════════════════════════
                sectionWithHighlight(
                  'advanced',
                  AdvancedSection(key: _sectionKeys['advanced']),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
