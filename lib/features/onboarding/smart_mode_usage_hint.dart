/// Post-usage Smart Mode discovery touchpoint —
/// `.scratch/smart-mode-v2/issues/08-onboarding-touchpoints.md`.
///
/// [SmartModeUsageHintWatcher] shows a dezent, one-time hint after the first
/// completed dictation for users who have not engaged with Smart Mode
/// (standard preset still `off`) — covering both onboarding-skippers and
/// pre-existing users who onboarded before this feature shipped. Unlike the
/// feature spotlight (`feature_spotlight_notice.dart`) this never recurs and
/// never bundles multiple entries: it is a single, dismiss-and-forget nudge,
/// not a recurring prompt (explicitly out of scope per the parent ticket,
/// same reasoning that rules out mirroring the sponsoring hint's cadence).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart' show HistoryEntry;
import '../../core/data/history_providers.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../core/theme/tokens.dart';
import '../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../settings/sections/smart_mode_section.dart'
    show startSmartModeDownloadWithRamCheck;

/// How much of the raw dictated text is quoted in the hint dialog — enough
/// to be recognizable as "the thing you just said", not a full transcript
/// re-read (History already owns that view).
const int kSmartModeUsageHintTextPreviewLength = 160;

/// Wraps [child], watching [historyEntriesProvider] for a newly completed
/// dictation. Renders no visible UI of its own — place it anywhere above the
/// content layer, same convention as [WpFeatureSpotlightWatcher] and
/// [WpStoreThankYouWatcher].
class SmartModeUsageHintWatcher extends ConsumerStatefulWidget {
  const SmartModeUsageHintWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SmartModeUsageHintWatcher> createState() =>
      _SmartModeUsageHintWatcherState();
}

class _SmartModeUsageHintWatcherState
    extends ConsumerState<SmartModeUsageHintWatcher> {
  bool _dialogShowing = false;
  String? _lastSeenEntryId;
  bool _initialized = false;

  bool _eligible(AppSettings settings) {
    if (settings.smartMode.standardPreset != 'off') return false;
    if (settings.onboarding.smartModeUsageHintShown) return false;
    final revisionRunning = ref.read(onboardingRevisionRunProvider);
    final manuallyOpen = ref.read(onboardingManuallyOpenProvider);
    return !onboardingSurfaceActive(
      onboardingCompleted: settings.onboarding.onboardingCompleted,
      manuallyOpen: manuallyOpen,
      revisionRunning: revisionRunning,
    );
  }

  Future<void> _markShown() async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(smartModeUsageHintShown: true),
          ),
        );
  }

  Future<void> _showHint(String dictatedText) async {
    _dialogShowing = true;
    final l10n = L10n.of(context);
    final preview = dictatedText.length > kSmartModeUsageHintTextPreviewLength
        ? '${dictatedText.substring(0, kSmartModeUsageHintTextPreviewLength)}…'
        : dictatedText;
    await showWpDialog<void>(
      context: context,
      title: l10n.smartModeUsageHintTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.smartModeUsageHintBody),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '"$preview"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
      actions: [
        WpButton(
          label: l10n.smartModeUsageHintDismiss,
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: WpSpacing.sm),
        WpButton(
          label: l10n.smartModeUsageHintCta,
          variant: WpButtonVariant.primary,
          onPressed: () {
            final notifier = ref.read(smartModeDownloadProvider.notifier);
            Navigator.of(context).pop();
            startSmartModeDownloadWithRamCheck(
              context: context,
              notifier: notifier,
              l10n: l10n,
            );
          },
        ),
      ],
    );
    await _markShown();
    _dialogShowing = false;
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read from the listener below) so the provider starts
    // resolving as soon as this widget mounts — by the time a real dictation
    // completes, minutes into a session at the earliest, settings are always
    // long since loaded.
    final settingsAsync = ref.watch(settingsProvider);
    ref.listen<AsyncValue<List<HistoryEntry>>>(historyEntriesProvider, (
      prev,
      next,
    ) {
      final entries = next.value;
      if (entries == null || entries.isEmpty) return;
      final newestId = entries.first.id;
      if (!_initialized) {
        // First emission after mount just establishes the baseline — it can
        // be pre-existing history from a previous session, not a dictation
        // that "just completed".
        _initialized = true;
        _lastSeenEntryId = newestId;
        return;
      }
      if (newestId == _lastSeenEntryId) return;
      _lastSeenEntryId = newestId;
      if (_dialogShowing) return;
      final settings = settingsAsync.value;
      if (settings == null || !_eligible(settings)) return;
      unawaited(_showHint(entries.first.content));
    });
    return widget.child;
  }
}
