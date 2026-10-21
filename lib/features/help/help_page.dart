/// The Help hub (WP-78): the rail's Hilfe entry opens the handbook first. The
/// introduction, support and diagnostics are one tab away. A deep link from
/// Settings picks the tab (and a chapter slug picks the handbook chapter).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show redactSensitive, sanitizePaths;

import '../../core/app_info.dart';
import '../../core/app_urls.dart';
import '../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/navigation/help_target.dart';
import '../../core/navigation/page_state.dart';
import '../../core/sponsors.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/generated/wp_tokens.g.dart';
import '../../core/theme/tokens.dart';
import '../feedback/feedback_type.dart';
import '../../services/stt/stt_bundle.dart';
import '../../services/stt_parakeet/parakeet_engine_notifier.dart';
import '../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelId;
import '../../widgets/page_shell.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_tabs.dart';
import '../../widgets/wp_text_link.dart';
import '../settings/sections/interface_section.dart' show SponsorChipRow;
import '../settings/sections/onboarding_review_section.dart';
import '../settings/sections/review_support_section.dart';
import '../settings/widgets/wp_settings_group.dart';
import 'diagnostics_report.dart';
import 'manual/user_manual_view.dart';
import 'support_page.dart';
import '../../widgets/external_link.dart';

/// A URL as a reader sees it: no scheme, no trailing slash.
String _displayUrl(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

/// The issue tracker as a reader sees it: no scheme.
const String _issuesUrl = '$kGitHubRepoUrl/issues';

class HelpPage extends ConsumerStatefulWidget {
  const HelpPage({super.key});

  @override
  ConsumerState<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends ConsumerState<HelpPage> {
  HelpTab _tab = HelpTab.manual;
  String? _chapterSlug;
  String? _query;

  /// Bumped on every deep link, so the handbook opens on the requested
  /// chapter even when it was already on screen.
  int _handbookEpoch = 0;

  @override
  void initState() {
    super.initState();
    // A link set before this page mounted: the Settings search jumps here
    // through the page switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consumeTarget(ref.read(helpTargetProvider));
    });
  }

  /// Applies [target] once and clears it, so a later visit starts afresh.
  void _consumeTarget(HelpTarget? target) {
    if (target == null) return;
    ref.read(helpTargetProvider.notifier).set(null);
    setState(() {
      _tab = target.tab;
      _chapterSlug = target.chapterSlug;
      _query = target.query;
      _handbookEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HelpTarget?>(helpTargetProvider, (_, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumeTarget(ref.read(helpTargetProvider));
      });
    });
    final l10n = L10n.of(context);
    final langCode = ref.watch(localeProvider).languageCode;

    return WpPageShell(
      scrollable: false,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The app shell already shows the page title ("Hilfe"); a second
          // header here doubled it.
          WpTabs(
            labels: [
              l10n.helpTabManual,
              l10n.helpTabIntro,
              l10n.helpTabSupport,
              l10n.helpTabDiagnostics,
            ],
            selectedIndex: _tab.index,
            onSelected: (i) => setState(() => _tab = HelpTab.values[i]),
            itemKeys: [
              for (final tab in HelpTab.values)
                ValueKey('help-hub-tab-${tab.name}'),
            ],
            itemIdentifiers: [
              for (final tab in HelpTab.values) 'help-hub-tab-${tab.name}',
            ],
          ),
        ],
      ),
      child: _body(l10n, langCode),
    );
  }

  Widget _body(L10n l10n, String langCode) => switch (_tab) {
    HelpTab.manual => KeyedSubtree(
      key: ValueKey('handbook-$_handbookEpoch'),
      child: UserManualView(initialSlug: _chapterSlug, initialQuery: _query),
    ),
    HelpTab.intro => const _Scrolling(child: OnboardingReviewSection()),
    HelpTab.support => _Scrolling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Feedback and ideas come first: the two entry points into the
          // same form, the idea one with its type preset (FB-02).
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            children: [
              Semantics(
                identifier: 'help-feedback-button',
                child: WpButton(
                  key: const ValueKey('help-feedback-button'),
                  label: l10n.navFeedback,
                  variant: WpButtonVariant.primary,
                  icon: LucideIcons.messageSquare,
                  onPressed: () {
                    ref.read(feedbackPresetTypeProvider.notifier).set(null);
                    ref.read(activePageProvider.notifier).setPage('feedback');
                  },
                ),
              ),
              Semantics(
                identifier: 'help-idea-button',
                child: WpButton(
                  key: const ValueKey('help-idea-button'),
                  label: l10n.menuBarHelpIdea,
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  icon: LucideIcons.lightbulb,
                  onPressed: () {
                    ref
                        .read(feedbackPresetTypeProvider.notifier)
                        .set(FeedbackType.idea);
                    ref.read(activePageProvider.notifier).setPage('feedback');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),
          const ReviewSupportSection(),
          const SizedBox(height: WpSpacing.lg),
          WpSettingsGroup(
            heading: l10n.supportPageTitle,
            children: const [SponsorChipRow()],
          ),
          if (kSponsors.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.lg),
            _SponsorsCard(title: l10n.aboutSponsorsTitle),
          ],
          const SizedBox(height: WpSpacing.lg),
          const SupportPage(embedded: true),
        ],
      ),
    ),
    HelpTab.diagnostics => _Scrolling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DiagnosticsSection(),
          const SizedBox(height: WpSpacing.lg),
          WpSettingsGroup(
            heading: l10n.helpLegalTitle,
            children: [
              WpSettingsRow(
                rowId: 'help-privacy-policy',
                title: l10n.aboutPrivacyPolicy,
                subtitle: _displayUrl(privacyPolicyUrl(langCode)),
                trailing: Semantics(
                  identifier: 'settings-help-privacy-policy',
                  child: WpButton(
                    key: const ValueKey('settings-help-privacy-policy'),
                    label: l10n.actionOpen,
                    semanticsLabel: l10n.actionOpenNamed(
                      l10n.aboutPrivacyPolicy,
                    ),
                    variant: WpButtonVariant.ghost,
                    tone: WpButtonTone.neutral,
                    icon: LucideIcons.externalLink,
                    onPressed: () =>
                        openExternalUrl(context, privacyPolicyUrl(langCode)),
                  ),
                ),
              ),
              WpSettingsRow(
                rowId: 'help-imprint',
                title: l10n.aboutImprint,
                subtitle: _displayUrl(imprintUrl(langCode)),
                trailing: Semantics(
                  identifier: 'settings-help-imprint',
                  child: WpButton(
                    key: const ValueKey('settings-help-imprint'),
                    label: l10n.actionOpen,
                    semanticsLabel: l10n.actionOpenNamed(l10n.aboutImprint),
                    variant: WpButtonVariant.ghost,
                    tone: WpButtonTone.neutral,
                    icon: LucideIcons.externalLink,
                    onPressed: () =>
                        openExternalUrl(context, imprintUrl(langCode)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  };
}

/// The opted-in sponsors, shown only while the list in `sponsors.dart` has
/// entries (see SPONSORS.md).
class _SponsorsCard extends StatelessWidget {
  const _SponsorsCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return WpSettingsGroup(
      heading: title,
      children: [
        Wrap(
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.sm,
          children: [
            for (final sponsor in kSponsors)
              if (sponsor.url == null)
                Text(sponsor.name)
              else
                WpTextLink(
                  label: sponsor.name,
                  icon: LucideIcons.externalLink,
                  onPressed: () => openExternalUrl(context, sponsor.url!),
                ),
          ],
        ),
      ],
    );
  }
}

/// A tab body that scrolls when it is taller than the window.
class _Scrolling extends StatelessWidget {
  const _Scrolling({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: WpSpacing.xl),
      child: child,
    );
  }
}

/// The text the Diagnose tab shows and copies when the full report cannot be
/// gathered. The error is localized and cleared of secrets and user paths
/// first, because it may echo either (GS-042).
String diagnosticsFallbackReport(Object error, L10n l10n) =>
    'WhisPaste v$appVersion\n'
    'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
    '${l10n.aboutDiagnosticsIncomplete(sanitizePaths(redactSensitive('$error')))}';

/// Gathers the diagnostics report the Diagnose tab previews and copies. A
/// provider, so tests can supply a fixed report instead of probing the host.
final helpReportProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => _gatherReport(ref),
);

Future<String> _gatherReport(Ref ref) async {
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  final isParakeet = settings.onDeviceEngine == OnDeviceEngine.parakeet;

  if (isParakeet) {
    final parakeet = ref.read(parakeetEngineProvider);
    return gatherDiagnosticsReport(
      engine: OnDeviceEngine.parakeet.value,
      sttServerState: parakeet.state.name,
      sttErrorMessage: parakeet.errorMessage,
      backend: 'cpu',
      loadedModel: parakeetModelId,
    );
  }
  final stt = ref.read(localSttBundleProvider);
  final engineStatus = ref.read(whisperEngineProvider).status;
  return gatherDiagnosticsReport(
    engine: OnDeviceEngine.whisper.value,
    sttServerState: stt.serverState.name,
    sttErrorMessage: stt.errorMessage,
    backend: engineStatus.backend.name,
    cpuFeatures: engineStatus.cpuFeatures,
    loadedModel: stt.modelId.isEmpty ? null : stt.modelId,
    cpuFallbackActive: stt.cpuFallbackActive,
  );
}

/// The Diagnose tab: copy the report, preview exactly what it contains, and
/// report an issue. The preview opens below the rows, so a reader sees the
/// contents before anything leaves the clipboard (Art. 13 transparency).
class _DiagnosticsSection extends ConsumerStatefulWidget {
  const _DiagnosticsSection();

  @override
  ConsumerState<_DiagnosticsSection> createState() =>
      _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<_DiagnosticsSection> {
  bool _copied = false;
  bool _busy = false;
  bool _previewOpen = false;
  Future<String>? _preview;

  /// The report, or the minimal fallback block when gathering throws.
  Future<String> _report(L10n l10n) async {
    try {
      return await ref.read(helpReportProvider)();
    } on Object catch (e) {
      return diagnosticsFallbackReport(e, l10n);
    }
  }

  void _togglePreview(L10n l10n) {
    setState(() {
      _previewOpen = !_previewOpen;
      _preview = _previewOpen ? _report(l10n) : null;
    });
  }

  Future<void> _copy(L10n l10n) async {
    if (_busy) return;
    setState(() => _busy = true);
    final text = await _report(l10n);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _copied = true;
    });
    WpToast.show(context, message: l10n.aboutCopied, type: WpToastType.success);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Label and icon carry the confirmation, and because the label *is* the
    // accessible name a screen reader hears "Kopiert!" too. The button's tones
    // are accent/neutral/danger, and there is no success among them, so the
    // check-check glyph plus the changed word carry the message instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSettingsGroup(
          heading: l10n.helpTabDiagnostics,
          children: [
            WpSettingsRow(
              rowId: 'help-diagnostics',
              title: l10n.aboutSystemInfo,
              subtitle: l10n.aboutSystemInfoDesc,
              trailing: Semantics(
                identifier: 'help-diagnostics-copy',
                child: WpButton(
                  key: const ValueKey('help-diagnostics-copy'),
                  label: _copied ? l10n.aboutCopied : l10n.aboutCopyDebugInfo,
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  icon: _copied ? LucideIcons.checkCheck : LucideIcons.copy,
                  isLoading: _busy,
                  onPressed: () => _copy(l10n),
                ),
              ),
            ),
            WpSettingsRow(
              rowId: 'help-diagnostics-preview',
              title: l10n.aboutDiagnosticsContentsTitle,
              subtitle: l10n.aboutDiagnosticsContentsDesc,
              trailing: Semantics(
                identifier: 'help-diagnostics-preview',
                child: WpButton(
                  key: const ValueKey('help-diagnostics-preview'),
                  label: _previewOpen
                      ? l10n.aboutDiagnosticsPreviewHide
                      : l10n.aboutDiagnosticsPreviewShow,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  icon: _previewOpen
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  onPressed: () => _togglePreview(l10n),
                ),
              ),
            ),
            WpSettingsRow(
              rowId: 'help-report-issue',
              title: l10n.aboutReportIssue,
              subtitle: _issuesUrl.replaceFirst('https://', ''),
              trailing: Semantics(
                identifier: 'settings-help-report-issue',
                child: WpButton(
                  key: const ValueKey('settings-help-report-issue'),
                  label: l10n.actionOpen,
                  semanticsLabel: l10n.actionOpenNamed(l10n.aboutReportIssue),
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  icon: LucideIcons.externalLink,
                  onPressed: () => openExternalUrl(context, _issuesUrl),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.helpDiagnosticsPublicNote,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        if (_busy) ...[
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            label: l10n.helpDiagnosticsBuilding,
            liveRegion: true,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.helpDiagnosticsBuilding,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: WpColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_preview != null) ...[
          const SizedBox(height: WpSpacing.md),
          _ReportPreview(report: _preview!),
        ],
      ],
    );
  }
}

/// The report text as it will be copied, in a bounded, selectable box.
class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.report});

  final Future<String> report;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: report,
      builder: (context, snapshot) {
        final text = snapshot.data;
        return Container(
          key: const ValueKey('help-diagnostics-preview-box'),
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: WpColors.surfaceVariant,
            borderRadius: BorderRadius.circular(WpRadiusTokens.sm),
            border: Border.all(color: WpColors.borderSubtle),
          ),
          child: text == null
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    text,
                    key: const ValueKey('help-diagnostics-preview-text'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: WpTypography.caption,
                      height: 1.4,
                      color: WpColors.textPrimary,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
