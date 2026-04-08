import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../widgets/page_shell.dart';
import 'sections/cloud_advanced_section.dart';
import 'sections/feedback_section.dart';
import 'sections/interface_section.dart';
import 'sections/overlay_button_section.dart';
import 'sections/postprocessing_section.dart';
import 'sections/recording_sections.dart';
import 'sections/stt_section.dart';
import 'settings_widgets.dart';

/// Settings page — thin coordinator that composes extracted section widgets.
///
/// Supports deep-linking: when [settingsScrollTargetProvider] contains a
/// section id (e.g. `'stt'`, `'postprocessing'`), the page scrolls to
/// that section on mount and clears the target.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _sectionKeys = <String, GlobalKey>{
    'audio': GlobalKey(),
    'recordingSafety': GlobalKey(),
    'afterTranscription': GlobalKey(),
    'stt': GlobalKey(),
    'sttModel': GlobalKey(),
    'postprocessing': GlobalKey(),
    'replacements': GlobalKey(),
    'hotkey': GlobalKey(),
    'sound': GlobalKey(),
    'overlay': GlobalKey(),
    'interface': GlobalKey(),
    'cloud': GlobalKey(),
    'advanced': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    // Scroll to target section after the first frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTargetIfNeeded();
    });
  }

  void _scrollToTargetIfNeeded() {
    final target = ref.read(settingsScrollTargetProvider);
    if (target == null) return;

    // Clear immediately to avoid repeat scrolls.
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

  @override
  Widget build(BuildContext context) {
    // Watch for scroll target changes while the page is visible.
    ref.listen(settingsScrollTargetProvider, (_, target) {
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTargetIfNeeded();
        });
      }
    });

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══════════════════════════════════════════
          //  RECORDING PIPELINE
          // ═══════════════════════════════════════════
          AudioSection(key: _sectionKeys['audio']),
          settingsSectionDivider(context),
          RecordingSafetySection(key: _sectionKeys['recordingSafety']),
          settingsSectionDivider(context),
          AfterTranscriptionSection(key: _sectionKeys['afterTranscription']),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  TRANSCRIPTION & ENHANCEMENT
          // ═══════════════════════════════════════════
          SpeechRecognitionSection(key: _sectionKeys['stt']),
          settingsSectionDivider(context),
          PostProcessingSection(key: _sectionKeys['postprocessing']),
          settingsSectionDivider(context),
          TextReplacementsSection(key: _sectionKeys['replacements']),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  SHORTCUTS & FEEDBACK
          // ═══════════════════════════════════════════
          KeyboardShortcutSection(key: _sectionKeys['hotkey']),
          settingsSectionDivider(context),
          SoundFeedbackSection(key: _sectionKeys['sound']),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  DISPLAY & LAYOUT
          // ═══════════════════════════════════════════
          OverlayButtonSection(key: _sectionKeys['overlay']),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  GENERAL
          // ═══════════════════════════════════════════
          InterfaceSection(key: _sectionKeys['interface']),
          settingsSectionDivider(context),
          CloudProvidersSection(key: _sectionKeys['cloud']),
          settingsSectionDivider(context),
          AdvancedSection(key: _sectionKeys['advanced']),
        ],
      ),
    );
  }
}