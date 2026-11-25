/// The Help hub (ticket): the rail's Hilfe entry opens the handbook first. The
/// introduction, feedback & contact, support and diagnostics are one tab away.
/// Feedback & contact holds every way to reach the team; support holds only
/// the ways to support the project (#395). A deep link from Settings picks the
/// tab (and a chapter slug picks the handbook chapter).
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
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
import '../../widgets/wp_tabs.dart';
import '../../widgets/wp_text_link.dart';
import '../settings/sections/interface_section.dart' show SponsorChipRow;
import '../settings/sections/onboarding_review_section.dart';
import '../settings/widgets/wp_settings_group.dart';
import 'diagnostics_report.dart';
import 'manual/user_manual_view.dart';
import 'support_page.dart';
import '../../widgets/external_link.dart';
import '../../widgets/wp_copy_feedback.dart';

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

    // Shell pattern (#197): the tab bar is the fixed strip; each tab owns its
    // one scroll view, which carries the page inset itself, so the scrollbar
    // sits at the window edge and no empty band stays above scrolling content.
    return WpPageShell(
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The app shell already shows the page title ("Hilfe"); a second
          // header here doubled it.
          WpTabs(
            labels: [
              l10n.helpTabManual,
              l10n.helpTabIntro,
              l10n.helpTabFeedback,
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
    // The handbook keeps a fixed search above its own scroll views, so it
    // takes the inset from outside.
    HelpTab.manual => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        WpPageFrame.inset,
        WpPageFrame.titleToContent,
        WpPageFrame.inset,
        0,
      ),
      child: KeyedSubtree(
        key: ValueKey('handbook-$_handbookEpoch'),
        child: UserManualView(initialSlug: _chapterSlug, initialQuery: _query),
      ),
    ),
    HelpTab.intro => const _Scrolling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [OnboardingReviewSection()],
      ),
    ),
    HelpTab.feedback => const _Scrolling(child: _FeedbackContactSection()),
    HelpTab.support => _Scrolling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SupportPage(embedded: true),
          if (kSponsors.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.lg),
            _SponsorsCard(title: l10n.aboutSponsorsTitle),
          ],
          const SizedBox(height: WpSpacing.lg),
          WpSettingsGroup(
            heading: l10n.supportPageTitle,
            children: const [SponsorChipRow()],
          ),
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
                trailing: WpTextLink(
                  key: const ValueKey('settings-help-privacy-policy'),
                  testID: 'settings-help-privacy-policy',
                  label: l10n.actionOpen,
                  semanticsLabel: l10n.actionOpenNamed(l10n.aboutPrivacyPolicy),
                  kind: WpLinkKind.web,
                  onPressed: () =>
                      openExternalUrl(context, privacyPolicyUrl(langCode)),
                ),
              ),
              WpSettingsRow(
                rowId: 'help-imprint',
                title: l10n.aboutImprint,
                subtitle: _displayUrl(imprintUrl(langCode)),
                trailing: WpTextLink(
                  key: const ValueKey('settings-help-imprint'),
                  testID: 'settings-help-imprint',
                  label: l10n.actionOpen,
                  semanticsLabel: l10n.actionOpenNamed(l10n.aboutImprint),
                  kind: WpLinkKind.web,
                  onPressed: () =>
                      openExternalUrl(context, imprintUrl(langCode)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  };
}

/// The Feedback & contact tab: the feedback form, a problem report, ideas
/// (form and public board) and the contact address. No support entries: those
/// are on the support tab.
class _FeedbackContactSection extends ConsumerWidget {
  const _FeedbackContactSection();

  void _openForm(WidgetRef ref, FeedbackType? type) {
    ref.read(feedbackPresetTypeProvider.notifier).set(type);
    ref.read(activePageProvider.notifier).setPage('feedback');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'help-feedback-section',
      child: WpSettingsGroup(
        heading: l10n.helpTabFeedback,
        children: [
          WpSettingsRow(
            rowId: 'help-contact-form',
            title: l10n.feedbackTitle,
            subtitle: l10n.helpFeedbackFormDesc,
            trailing: Semantics(
              identifier: 'help-feedback-button',
              child: WpButton(
                key: const ValueKey('help-feedback-button'),
                label: l10n.helpFeedbackFormAction,
                variant: WpButtonVariant.primary,
                icon: LucideIcons.messageSquare,
                onPressed: () => _openForm(ref, null),
              ),
            ),
          ),
          WpSettingsRow(
            rowId: 'help-report-problem',
            title: l10n.aboutReportIssue,
            subtitle: l10n.helpReportProblemDesc,
            trailing: Semantics(
              identifier: 'help-problem-button',
              child: WpButton(
                key: const ValueKey('help-problem-button'),
                label: l10n.helpReportProblemAction,
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                icon: LucideIcons.bug,
                onPressed: () => _openForm(ref, FeedbackType.problem),
              ),
            ),
          ),
          WpSettingsRow(
            rowId: 'advanced-ideas',
            title: l10n.ideasBoardLabel,
            subtitle: l10n.helpIdeasDesc,
            trailing: Wrap(
              spacing: WpSpacing.sm,
              runSpacing: WpSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  identifier: 'help-idea-button',
                  child: WpButton(
                    key: const ValueKey('help-idea-button'),
                    label: l10n.helpIdeaAction,
                    variant: WpButtonVariant.secondary,
                    tone: WpButtonTone.neutral,
                    icon: LucideIcons.lightbulb,
                    onPressed: () => _openForm(ref, FeedbackType.idea),
                  ),
                ),
                WpTextLink(
                  key: const ValueKey('help-ideas-board-link'),
                  testID: 'help-ideas-board-link',
                  label: l10n.ideasBoardAction,
                  kind: WpLinkKind.web,
                  onPressed: () => openExternalUrl(context, kVotepitBoardUrl),
                ),
              ],
            ),
          ),
          WpSettingsRow(
            rowId: 'help-contact-mail',
            title: l10n.helpContactMailTitle,
            trailing: WpTextLink(
              key: const ValueKey('help-contact-mail-link'),
              testID: 'help-contact-mail-link',
              label: kContactEmail,
              semanticsLabel: l10n.helpContactMailAction(kContactEmail),
              kind: WpLinkKind.web,
              onPressed: () =>
                  openExternalUrl(context, 'mailto:$kContactEmail'),
            ),
          ),
        ],
      ),
    );
  }
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
                  kind: WpLinkKind.web,
                  onPressed: () => openExternalUrl(context, sponsor.url!),
                ),
          ],
        ),
      ],
    );
  }
}

/// A tab body that scrolls when it is taller than the window, with the same
/// scroll view and inset [WpPageShell] gives a scrollable page (#197): the
/// padding lives inside the scroll, so content scrolls up to the tab bar.
class _Scrolling extends StatelessWidget {
  const _Scrolling({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        WpPageFrame.inset,
        WpPageFrame.titleToContent,
        WpPageFrame.inset,
        WpPageFrame.bottom,
      ),
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

/// How long the Diagnose tab waits for the report before it shows the
/// fallback block instead of a spinner that never ends (#1635).
const Duration kDiagnosticsReportTimeout = Duration(seconds: 10);

/// Runs [gather] and falls back to [diagnosticsFallbackReport] when it throws
/// or does not finish within [timeout], so the preview and the copy button
/// always end.
Future<String> diagnosticsReportWithin(
  Future<String> Function() gather,
  L10n l10n, {
  Duration timeout = kDiagnosticsReportTimeout,
}) async {
  try {
    return await gather().timeout(timeout);
  } on TimeoutException {
    return diagnosticsFallbackReport(l10n.helpDiagnosticsTimedOut, l10n);
  } on Object catch (e) {
    return diagnosticsFallbackReport(e, l10n);
  }
}

/// Gathers the diagnostics report the Diagnose tab previews and copies. A
/// provider, so tests can supply a fixed report instead of probing the host.
final helpReportProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => _gatherReport(ref),
);

Future<String> _gatherReport(Ref ref) async {
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  final isParakeet = settings.onDeviceEngine == OnDeviceEngine.parakeet;

  if (settings.onDeviceEngine == OnDeviceEngine.system) {
    // Apple's engine runs in the system: no model or server state of ours.
    return gatherDiagnosticsReport(
      engine: OnDeviceEngine.system.value,
      sttServerState: 'ready',
      backend: 'system',
    );
  }
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
    backend: engineStatus.deviceBackend.name,
    cpuFeatures: engineStatus.cpuFeatures,
    loadedModel: stt.modelId.isEmpty ? null : stt.modelId,
    cpuFallbackActive: stt.cpuFallbackActive,
  );
}

/// The Diagnose tab: copy the report, preview exactly what it contains, and
/// report an issue. The preview opens right under its own row, so a reader
/// sees the contents before anything leaves the clipboard (Art. 13
/// transparency) and does not have to look for them further down.
class _DiagnosticsSection extends ConsumerStatefulWidget {
  const _DiagnosticsSection();

  @override
  ConsumerState<_DiagnosticsSection> createState() =>
      _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<_DiagnosticsSection> {
  bool _previewOpen = false;
  Future<String>? _preview;
  bool _busy = false;

  /// The report, or the minimal fallback block when gathering throws or
  /// takes too long.
  Future<String> _report(L10n l10n) =>
      diagnosticsReportWithin(ref.read(helpReportProvider), l10n);

  void _togglePreview(L10n l10n) {
    setState(() {
      _previewOpen = !_previewOpen;
      _preview = _previewOpen ? _report(l10n) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
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
                child: WpCopyButton(
                  testId: 'help-diagnostics-copy',
                  label: l10n.aboutCopyDebugInfo,
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  text: () => _report(l10n),
                  onBusyChanged: (busy) => setState(() => _busy = busy),
                ),
              ),
            ),
            // One group child, so no divider falls between row and preview.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                if (_preview != null) ...[
                  _ReportPreview(report: _preview!),
                  const SizedBox(height: WpSpacing.sm),
                ],
              ],
            ),
            WpSettingsRow(
              rowId: 'help-report-issue',
              title: l10n.aboutReportIssue,
              subtitle: _issuesUrl.replaceFirst('https://', ''),
              trailing: WpTextLink(
                key: const ValueKey('settings-help-report-issue'),
                testID: 'settings-help-report-issue',
                label: l10n.actionOpen,
                semanticsLabel: l10n.actionOpenNamed(l10n.aboutReportIssue),
                kind: WpLinkKind.web,
                onPressed: () => openExternalUrl(context, _issuesUrl),
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
