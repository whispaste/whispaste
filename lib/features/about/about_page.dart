import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../../core/config/settings_provider.dart';
import '../../core/app_info.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/sponsors.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/stt/stt_bundle.dart';
import '../../services/stt_parakeet/parakeet_engine_notifier.dart';
import '../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelId;
import '../../services/update_actions.dart';
import '../../services/update_service.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/section.dart';
import '../settings/settings_widgets.dart' show HotkeyDisplay;
import '../../widgets/wp_button.dart';
import '../../widgets/wp_focus_ring.dart';
import 'diagnostics_report.dart';

/// Opens [url] in the system browser, silently doing nothing when the platform
/// can't handle it.
///
/// Four call sites on this page used to inline the same two-line
/// `canLaunchUrl`/`launchUrl` closure.
Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// About page — app info, version, open-source links, support, credits,
/// keyboard shortcuts, privacy, and system diagnostics.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = Theme.of(context).textTheme;
    final l10n = L10n.of(context);
    final langCode = ref.watch(localeProvider).languageCode;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final channel = ref.watch(deployChannelProvider);
    final updateState = ref.watch(updateProvider);
    // Always-on review & support entry: opens the Microsoft Store review
    // deep-link on Windows (where a store listing exists) and the GitHub
    // repository on macOS/Linux. Single-source URLs from app_urls.dart.
    final reviewSupportUrl = Platform.isWindows
        ? kWindowsStoreReviewUrl
        : kGitHubRepoUrl;
    // Resolved up front, like `updates_section.dart` does for the same action:
    // the button itself sits inside a collection-if and can't declare locals.
    final (updateIcon, updateLabel) = resolveUpdateActionDisplay(
      phase: updateState.phase,
      channel: channel,
      state: updateState,
      l10n: l10n,
    );
    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: WpSpacing.xl),

          // ── Brand hero ──
          const Center(child: WpBrandWordmark(height: 64)),
          const SizedBox(height: WpSpacing.md),
          Center(
            child: Text(l10n.aboutVersion(appVersion), style: ts.bodySmall),
          ),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              l10n.aboutTagline,
              style: ts.bodyMedium?.copyWith(color: WpColorsDark.textSecondary),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Quick actions ──
          //
          // Four peers in one row, so they share one look: the app's
          // `secondary` button on the `neutral` tone. Neutral rather than the
          // accent default because these sit directly under the brand hero and
          // are wayfinding, not the thing the page asks you to do — the accent
          // is spent one card further down, on Support.
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              WpButton(
                label: l10n.aboutWhatsNew,
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                icon: LucideIcons.sparkles,
                onPressed: () => _launchUrl('https://whispaste.de/changelog'),
              ),
              WpButton(
                label: l10n.aboutGitHub,
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                icon: FontAwesomeIcons.github.data,
                onPressed: () => _launchUrl(kGitHubRepoUrl),
              ),
              WpButton(
                label: l10n.aboutReportIssue,
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                icon: LucideIcons.circleAlert,
                onPressed: () => _launchUrl('$kGitHubRepoUrl/issues'),
              ),
              if (!isExternallyManaged(channel))
                WpButton(
                  label: updateLabel,
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  icon: updateIcon,
                  // The spinner takes the icon's slot rather than a slot of
                  // its own, so the button doesn't jump width while it works.
                  isLoading: updateState.isBusy,
                  // `isLoading` already disables, but spelling the null out
                  // keeps "busy means unpressable" readable at the call site.
                  onPressed: updateState.isBusy
                      ? null
                      : () => triggerUpdateAction(
                          ref: ref,
                          updateState: updateState,
                          channel: channel,
                        ),
                ),
            ],
          ),
          const SizedBox(height: WpSpacing.xl),

          // ── Support this project ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutSupportTitle,
            children: [
              Text(
                l10n.aboutSupportDescription,
                style: const TextStyle(
                  color: WpColorsDark.textSecondary,
                  fontSize: WpTypography.body,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: WpSpacing.md),
              // The one place on this page that keeps the accent tone: these
              // four are the ask. Same `secondary` box as the quick actions —
              // the hierarchy is carried by the label/icon colour, since the
              // outline is `borderSubtle` on both tones.
              Wrap(
                spacing: WpSpacing.sm,
                runSpacing: WpSpacing.sm,
                children: [
                  WpButton(
                    label: l10n.reviewSupportEntry,
                    variant: WpButtonVariant.secondary,
                    icon: LucideIcons.star,
                    onPressed: () => _launchUrl(reviewSupportUrl),
                  ),
                  WpButton(
                    label: l10n.aboutGitHubSponsors,
                    variant: WpButtonVariant.secondary,
                    icon: LucideIcons.heart,
                    onPressed: () => _launchUrl(kGitHubSponsorsUrl),
                  ),
                  WpButton(
                    label: l10n.aboutKofi,
                    variant: WpButtonVariant.secondary,
                    icon: FontAwesomeIcons.mugHot.data,
                    onPressed: () => _launchUrl(kKofiUrl),
                  ),
                  WpButton(
                    label: l10n.aboutStarOnGitHub,
                    variant: WpButtonVariant.secondary,
                    icon: LucideIcons.star,
                    onPressed: () => _launchUrl(kGitHubRepoUrl),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Sponsors (opt-in recognition, hidden while the list is empty
          // — see SPONSORS.md) ──
          if (kSponsors.isNotEmpty) ...[
            _AboutCard(
              isDark: isDark,
              title: l10n.aboutSponsorsTitle,
              children: [
                Wrap(
                  spacing: WpSpacing.sm,
                  runSpacing: WpSpacing.sm,
                  children: [
                    for (final sponsor in kSponsors)
                      _SponsorChip(sponsor: sponsor, isDark: isDark),
                  ],
                ),
              ],
            ),
            const SizedBox(height: WpSpacing.lg),
          ],

          // ── Built with ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutBuiltWith,
            children: [
              _BuiltWithRow(
                icon: LucideIcons.codeXml,
                title: l10n.aboutFlutterGo,
                description: l10n.aboutFlutterGoDesc,
                isDark: isDark,
              ),
              _BuiltWithRow(
                icon: LucideIcons.mic,
                title: l10n.aboutWhisper,
                description: l10n.aboutWhisperDesc,
                isDark: isDark,
              ),
              _BuiltWithRow(
                icon: LucideIcons.gauge,
                title: l10n.aboutParakeet,
                description: l10n.aboutParakeetDesc,
                isDark: isDark,
              ),
              _BuiltWithRow(
                icon: LucideIcons.shield,
                title: l10n.aboutPrivacyFirst,
                description: l10n.aboutPrivacyFirstDesc,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Privacy & Data ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutPrivacy,
            children: [
              _PrivacyPoint(text: l10n.aboutPrivacyLocal, isDark: isDark),
              _PrivacyPoint(text: l10n.aboutPrivacyCloud, isDark: isDark),
              _PrivacyPoint(text: l10n.aboutPrivacyNoTracking, isDark: isDark),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Keyboard shortcuts ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutKeyboardShortcuts,
            children: [
              _ShortcutRow(
                label: l10n.aboutShortcutRecord,
                // The app's keycap component, the same one Settings and the
                // onboarding use. This row used to flatten the very same
                // hotkey into one string and draw its own single wide cap, so
                // "Ctrl + Shift + V" appeared here as one key and three keys
                // two screens away.
                shortcut: HotkeyDisplay(
                  hotkeyKey: settings.hotkeyKey,
                  hotkeyModifiers: settings.hotkeyModifiers,
                  hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Links ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutLinks,
            children: [
              _LinkRow(
                icon: LucideIcons.globe,
                label: l10n.aboutWebsite,
                url: websiteHomeUrl(langCode),
                displayUrl: 'whispaste.de',
                isDark: isDark,
              ),
              _LinkRow(
                icon: FontAwesomeIcons.github.data,
                label: l10n.aboutGitHubRepo,
                url: kGitHubRepoUrl,
                displayUrl: kGitHubRepoUrl.replaceFirst('https://', ''),
                isDark: isDark,
              ),
              _LinkRow(
                icon: LucideIcons.scale,
                label: l10n.aboutMitLicense,
                url: '$kGitHubRepoUrl/blob/main/LICENSE',
                displayUrl: l10n.aboutViewOnGitHub,
                isDark: isDark,
              ),
              _LinkRow(
                icon: LucideIcons.fileText,
                label: l10n.aboutPrivacyPolicy,
                url: privacyPolicyUrl(langCode),
                displayUrl: privacyPolicyUrl(
                  langCode,
                ).replaceFirst('https://', '').replaceFirst(RegExp(r'/$'), ''),
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── System diagnostics ──
          _AboutCard(
            isDark: isDark,
            title: l10n.aboutSystemInfo,
            children: [
              Text(
                l10n.aboutSystemInfoDesc,
                style: const TextStyle(
                  color: WpColorsDark.textSecondary,
                  fontSize: WpTypography.body,
                ),
              ),
              const SizedBox(height: WpSpacing.sm),
              const Align(
                alignment: Alignment.centerLeft,
                child: _CopyDiagnosticsButton(),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Credits ──
          Center(
            child: Text(
              l10n.aboutMadeWith,
              style: ts.bodySmall?.copyWith(color: WpColorsDark.textMuted),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              l10n.aboutOpenSource,
              style: ts.bodySmall?.copyWith(
                color: WpColorsDark.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
        ],
      ),
    );
  }
}

// ─── About card ────────────────────────────────────────────────────────────

/// Surface card that groups one About section (header + its content) so the
/// page reads as structured panels rather than a flat document. Tokens only:
/// elevated surface, subtle border, [WpRadius.borderLg], [WpSpacing.lg] pad.
///
/// The header is a plain [WpSection] — the same one Settings and Analytics
/// use — so About no longer carries a section head of its own.
class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.isDark,
    required this.title,
    required this.children,
  });

  final bool isDark;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.lg),
      decoration: BoxDecoration(
        color: WpColorsDark.surfaceElevated,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: WpColorsDark.borderSubtle),
      ),
      // The card already pads itself — the section only supplies the header.
      child: WpSection(
        title: title,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

// ─── Shared tap surface ──────────────────────────────────────────────────────

/// Gives one of this page's hand-built affordances the interaction contract
/// every other tappable thing in the app already has: keyboard reach,
/// Enter/Space activation, the shared [WpFocusRing], and correct semantics.
///
/// Every interactive element on this page used to be a bare [GestureDetector],
/// which is pointer-only — the whole page was unreachable by keyboard in an
/// app whose promise is to never make you touch the mouse. It also carried a
/// `Semantics(label: X)` above a subtree that renders `Text(X)`; the label is
/// *prepended*, not substituted, so every one of them announced twice
/// (`_LinkRow` announced four fragments). Hence the house idiom from
/// `section.dart`/`wp_filter_chip.dart`: [MergeSemantics] plus a *label-less*
/// [Semantics], letting the visible text be the accessible name — `_LinkRow`
/// now announces its label and its URL as one sentence rather than four
/// fragments.
///
/// `button`/`link` still follow `onTap` rather than being hardcoded, even
/// though neither remaining caller can be disabled today — `_SponsorChip`
/// returns its bare chip when the sponsor has no URL and never wraps at all.
///
/// Scope note: this is what remains after the page's four *button* dialects
/// (quick action, update check, support, copy diagnostics) moved to
/// [WpButton]. It survives for the two affordances that are not buttons —
/// `_SponsorChip` and `_LinkRow`, each a full-width or free-form row that
/// paints its own surface — and it is deliberately *not* a restyle: ink and
/// hover are transparent here, the caller owns the look.
class _AboutTapTarget extends StatefulWidget {
  const _AboutTapTarget({
    required this.child,
    required this.onTap,
    this.isLink = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Announce as a link instead of a button (opens a URL in the browser).
  final bool isLink;

  @override
  State<_AboutTapTarget> createState() => _AboutTapTargetState();
}

class _AboutTapTargetState extends State<_AboutTapTarget> {
  static const double _radius = WpRadius.sm;

  final _focusNode = FocusNode(debugLabel: 'AboutTapTarget');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MergeSemantics(
      child: Semantics(
        button: enabled && !widget.isLink,
        link: enabled && widget.isLink,
        child: WpFocusRing(
          focusNode: _focusNode,
          // Both remaining callers paint a `WpRadius.sm` corner, so the ring
          // reads it from here rather than from a parameter nobody varies —
          // the pill-shaped callers that needed `WpRadius.lg` are now WpButtons.
          radius: _radius,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(_radius),
            // WpFocusRing owns all focus visuals; callers own their surface.
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ─── Sponsor chip ────────────────────────────────────────────────────────────

/// Displays a single opt-in sponsor entry (see `SPONSORS.md`). Tappable only
/// when [Sponsor.url] is set.
class _SponsorChip extends StatelessWidget {
  const _SponsorChip({required this.sponsor, required this.isDark});

  final Sponsor sponsor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const borderColor = WpColorsDark.borderSubtle;
    const textColor = WpColorsDark.textPrimary;

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        sponsor.name,
        style: const TextStyle(fontSize: WpTypography.body, color: textColor),
      ),
    );

    final url = sponsor.url;
    if (url == null) return chip;

    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      isLink: true,
      onTap: () => _launchUrl(url),
      child: chip,
    );
  }
}

// ─── Built-with row ──────────────────────────────────────────────────────────

class _BuiltWithRow extends StatelessWidget {
  const _BuiltWithRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: WpColorsDark.accentSubtle,
              borderRadius: WpRadius.borderSm,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: WpIconSize.sm, color: WpColorsDark.accent),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: WpTypography.subheading,
                    fontWeight: FontWeight.w600,
                    color: WpColorsDark.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: WpColorsDark.textSecondary,
                    fontSize: WpTypography.body,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Privacy point ───────────────────────────────────────────────────────────

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            // Off-scale on purpose: optical nudge aligning the check icon with
            // the first text line's cap height (body 13px at 1.5 line height).
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              LucideIcons.check,
              size: WpIconSize.xs,
              color: WpColorsDark.success,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WpColorsDark.textSecondary,
                fontSize: WpTypography.body,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shortcut row ────────────────────────────────────────────────────────────

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.shortcut});

  final String label;

  /// The keycaps themselves — always a [HotkeyDisplay]. Typed as a widget so
  /// this row stays a label/keycap layout and the app keeps exactly one thing
  /// that knows what a key looks like.
  final Widget shortcut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs + 1),
      child: Row(
        children: [
          Expanded(
            // bodyLarge, like _LinkRow's label directly below it. This row had
            // been on WpTypography.subheading + textSecondary, so the two
            // stacked list rows on the same card sat at different sizes and
            // colours. A deliberate visible change, not a side effect of the
            // keycap swap: the label grows slightly and darkens to
            // textPrimary so both rows read as one list.
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          shortcut,
        ],
      ),
    );
  }
}

// ─── Link row ────────────────────────────────────────────────────────────────

class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.displayUrl,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String url;
  final String displayUrl;
  final bool isDark;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // The old `label: '$label: $displayUrl'` sat above a subtree that renders
    // both strings, so this row announced all four fragments. Merging the two
    // rendered texts gives the same sentence once.
    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      isLink: true,
      onTap: () => _launchUrl(widget.url),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: WpMotion.durationFor(
            context,
            _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          ),
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? (WpColorsDark.hover)
                : (WpColorsDark.hoverTransparent),
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: WpIconSize.sm,
                color: WpColorsDark.textMuted,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Flexible(
                child: Text(
                  widget.displayUrl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WpColorsDark.textMuted,
                    fontSize: WpTypography.small,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              const Icon(
                LucideIcons.externalLink,
                size: WpIconSize.xs,
                color: WpColorsDark.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Copy diagnostics button ─────────────────────────────────────────────────

class _CopyDiagnosticsButton extends ConsumerStatefulWidget {
  const _CopyDiagnosticsButton();

  @override
  ConsumerState<_CopyDiagnosticsButton> createState() =>
      _CopyDiagnosticsButtonState();
}

class _CopyDiagnosticsButtonState
    extends ConsumerState<_CopyDiagnosticsButton> {
  bool _copied = false;
  bool _busy = false;

  Future<void> _copy() async {
    if (_busy) return;
    setState(() => _busy = true);

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final isParakeet = settings.onDeviceEngine == OnDeviceEngine.parakeet;

    String report;
    try {
      if (isParakeet) {
        final parakeet = ref.read(parakeetEngineProvider);
        report = await gatherDiagnosticsReport(
          engine: OnDeviceEngine.parakeet.value,
          sttServerState: parakeet.state.name,
          sttErrorMessage: parakeet.errorMessage,
          backend: 'cpu',
          loadedModel: parakeetModelId,
        );
      } else {
        final stt = ref.read(localSttBundleProvider);
        final engineBackend = ref
            .read(whisperEngineProvider)
            .status
            .backend
            .name;
        report = await gatherDiagnosticsReport(
          engine: OnDeviceEngine.whisper.value,
          sttServerState: stt.serverState.name,
          sttErrorMessage: stt.errorMessage,
          backend: engineBackend,
          loadedModel: stt.modelId.isEmpty ? null : stt.modelId,
          cpuFallbackActive: stt.cpuFallbackActive,
        );
      }
    } on Object catch (e) {
      // Never leave the user empty-handed — fall back to the minimal block.
      report =
          'WhisPaste v$appVersion\n'
          'OS: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}\n'
          'Diagnose unvollstaendig: $e';
    }

    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Label and icon carry the confirmation, and because the label *is* the
    // accessible name a screen reader hears "Kopiert!" too — the hardcoded
    // `Semantics(label:)` this button used to sit under pinned the
    // announcement to "Debug-Infos kopieren" forever.
    //
    // What the swap to WpButton costs: the success *green*. The button's tones
    // are accent/neutral/danger, and there is no success among them — adding
    // one for a single call site would put a fourth meaning into a shared
    // component to tint two seconds of feedback. The check-check glyph plus the
    // changed word carry the same message without it.
    return WpButton(
      label: _copied ? l10n.aboutCopied : l10n.aboutCopyDebugInfo,
      variant: WpButtonVariant.secondary,
      tone: WpButtonTone.neutral,
      icon: _copied ? LucideIcons.checkCheck : LucideIcons.copy,
      isLoading: _busy,
      onPressed: _copy,
    );
  }
}
