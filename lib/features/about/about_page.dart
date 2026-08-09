import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../../core/config/settings_labels.dart';
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
import '../../widgets/wp_focus_ring.dart';
import 'diagnostics_report.dart';

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
    final hotkeyLabel = formatHotkeyShortcut(
      settings.hotkeyModifiers,
      settings.hotkeyKey,
      separator: ' + ',
      l10n: l10n,
      displayOverride: settings.hotkey.hotkeyKeyDisplay,
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
              style: ts.bodyMedium?.copyWith(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Quick actions ──
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              _QuickAction(
                icon: LucideIcons.sparkles,
                label: l10n.aboutWhatsNew,
                url: 'https://whispaste.de/changelog',
                isDark: isDark,
              ),
              _QuickAction(
                icon: FontAwesomeIcons.github.data,
                label: l10n.aboutGitHub,
                url: kGitHubRepoUrl,
                isDark: isDark,
              ),
              _QuickAction(
                icon: LucideIcons.circleAlert,
                label: l10n.aboutReportIssue,
                url: '$kGitHubRepoUrl/issues',
                isDark: isDark,
              ),
              if (!isExternallyManaged(channel))
                // loam-ignore: a11y-interactive-semantics – semantics provided in _UpdateCheckAction.build
                _UpdateCheckAction(
                  updateState: updateState,
                  channel: channel,
                  isDark: isDark,
                  l10n: l10n,
                  onTap: () => triggerUpdateAction(
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
                style: TextStyle(
                  color: isDark
                      ? WpColorsDark.textSecondary
                      : WpColorsLight.textSecondary,
                  fontSize: WpTypography.body,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: WpSpacing.md),
              Wrap(
                spacing: WpSpacing.sm,
                runSpacing: WpSpacing.sm,
                children: [
                  _SupportButton(
                    icon: LucideIcons.star,
                    label: l10n.reviewSupportEntry,
                    url: reviewSupportUrl,
                    isDark: isDark,
                  ),
                  _SupportButton(
                    icon: LucideIcons.heart,
                    label: l10n.aboutGitHubSponsors,
                    url: kGitHubSponsorsUrl,
                    isDark: isDark,
                  ),
                  _SupportButton(
                    icon: FontAwesomeIcons.mugHot.data,
                    label: l10n.aboutKofi,
                    url: kKofiUrl,
                    isDark: isDark,
                  ),
                  _SupportButton(
                    icon: LucideIcons.star,
                    label: l10n.aboutStarOnGitHub,
                    url: kGitHubRepoUrl,
                    isDark: isDark,
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
                shortcut: hotkeyLabel,
                isDark: isDark,
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
                style: TextStyle(
                  color: isDark
                      ? WpColorsDark.textSecondary
                      : WpColorsLight.textSecondary,
                  fontSize: WpTypography.body,
                ),
              ),
              const SizedBox(height: WpSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: _CopyDiagnosticsButton(isDark: isDark),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Credits ──
          Center(
            child: Text(
              l10n.aboutMadeWith,
              style: ts.bodySmall?.copyWith(
                color: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              l10n.aboutOpenSource,
              style: ts.bodySmall?.copyWith(
                color: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
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
        color: isDark
            ? WpColorsDark.surfaceElevated
            : WpColorsLight.surfaceElevated,
        borderRadius: WpRadius.borderLg,
        border: Border.all(
          color: isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle,
        ),
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
/// [Semantics], letting the visible text be the accessible name. That also
/// keeps state honest for free — the copy button's label flips to "Kopiert!"
/// in the semantics tree because the rendered text is the name.
///
/// `button`/`link` follow `onTap`, so a disabled affordance (update check
/// while busy) stops advertising itself as pressable instead of lying.
///
/// Deliberately *not* a restyle: ink and hover are transparent here, each
/// caller keeps painting its own surface. Routing these four dialects through
/// [WpButton] is the right end state but changes how the page looks, so it
/// needs maintainer sign-off — see the audit befund.
class _AboutTapTarget extends StatefulWidget {
  const _AboutTapTarget({
    required this.child,
    required this.onTap,
    this.radius = WpRadius.sm,
    this.isLink = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Focus-ring corner radius. Pill-shaped callers pass [WpRadius.lg] rather
  /// than [WpRadius.full] — same choice `WpFilterChip` makes for its pill.
  final double radius;

  /// Announce as a link instead of a button (opens a URL in the browser).
  final bool isLink;

  @override
  State<_AboutTapTarget> createState() => _AboutTapTargetState();
}

class _AboutTapTargetState extends State<_AboutTapTarget> {
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
          radius: widget.radius,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(widget.radius),
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

// ─── Quick action pill ───────────────────────────────────────────────────────

class _QuickAction extends StatefulWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.url,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String url;
  final bool isDark;

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      radius: WpRadius.lg,
      isLink: true,
      onTap: () async {
        final uri = Uri.parse(widget.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: WpMotion.durationFor(
            context,
            _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                : (widget.isDark
                      ? WpColorsDark.surfaceVariant
                      : WpColorsLight.surfaceVariant),
            borderRadius: WpRadius.borderFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: WpIconSize.sm,
                color: widget.isDark
                    ? WpColorsDark.accent
                    : WpColorsLight.accent,
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark
                      ? WpColorsDark.textPrimary
                      : WpColorsLight.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Update check action ────────────────────────────────────────────────────

class _UpdateCheckAction extends StatefulWidget {
  const _UpdateCheckAction({
    required this.updateState,
    required this.channel,
    required this.isDark,
    required this.l10n,
    required this.onTap,
  });
  final UpdateState updateState;
  final DeployChannel channel;
  final bool isDark;
  final L10n l10n;
  final VoidCallback onTap;

  @override
  State<_UpdateCheckAction> createState() => _UpdateCheckActionState();
}

class _UpdateCheckActionState extends State<_UpdateCheckAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label) = _resolveDisplay();

    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      radius: WpRadius.lg,
      // Null while busy, so the semantics tree stops calling it a button for
      // as long as pressing it does nothing.
      onTap: widget.updateState.isBusy ? null : widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: WpMotion.durationFor(
            context,
            _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                : (widget.isDark
                      ? WpColorsDark.surfaceVariant
                      : WpColorsLight.surfaceVariant),
            borderRadius: WpRadius.borderFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.updateState.isBusy)
                SizedBox(
                  width: WpIconSize.sm,
                  height: WpIconSize.sm,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: widget.isDark
                        ? WpColorsDark.accent
                        : WpColorsLight.accent,
                  ),
                )
              else
                Icon(
                  icon,
                  size: WpIconSize.sm,
                  color: widget.isDark
                      ? WpColorsDark.accent
                      : WpColorsLight.accent,
                ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark
                      ? WpColorsDark.textPrimary
                      : WpColorsLight.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String) _resolveDisplay() => resolveUpdateActionDisplay(
    phase: widget.updateState.phase,
    channel: widget.channel,
    state: widget.updateState,
    l10n: widget.l10n,
  );
}

// ─── Support button ──────────────────────────────────────────────────────────

class _SupportButton extends StatefulWidget {
  const _SupportButton({
    required this.icon,
    required this.label,
    required this.url,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String url;
  final bool isDark;

  @override
  State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isDark
        ? WpColorsDark.accent
        : WpColorsLight.accent;
    final accentBadgeFill = widget.isDark
        ? WpColorsDark.accentBadgeFill
        : WpColorsLight.accentBadgeFill;
    final accentButtonFill = widget.isDark
        ? WpColorsDark.accentButtonFill
        : WpColorsLight.accentButtonFill;

    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      isLink: true,
      onTap: () async {
        final uri = Uri.parse(widget.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: WpMotion.durationFor(
            context,
            _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _hovered ? accentBadgeFill : accentButtonFill,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: WpIconSize.sm, color: accentColor),
              const SizedBox(width: WpSpacing.xs),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
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
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textColor = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

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
        style: TextStyle(fontSize: WpTypography.body, color: textColor),
      ),
    );

    final url = sponsor.url;
    if (url == null) return chip;

    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      isLink: true,
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
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
              color: isDark
                  ? WpColorsDark.accentSubtle
                  : WpColorsLight.accentSubtle,
              borderRadius: WpRadius.borderSm,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: WpIconSize.sm,
              color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: WpTypography.subheading,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? WpColorsDark.textPrimary
                        : WpColorsLight.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
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
          Padding(
            // Off-scale on purpose: optical nudge aligning the check icon with
            // the first text line's cap height (body 13px at 1.5 line height).
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              LucideIcons.check,
              size: WpIconSize.xs,
              color: isDark ? WpColorsDark.success : WpColorsLight.success,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
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
  const _ShortcutRow({
    required this.label,
    required this.shortcut,
    required this.isDark,
  });
  final String label;
  final String shortcut;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs + 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
                fontSize: WpTypography.subheading,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant,
              borderRadius: WpRadius.borderSm,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderDefault
                    : WpColorsLight.borderDefault,
              ),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textPrimary
                    : WpColorsLight.textPrimary,
                fontSize: WpTypography.small,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
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

  Future<void> _launch() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The old `label: '$label: $displayUrl'` sat above a subtree that renders
    // both strings, so this row announced all four fragments. Merging the two
    // rendered texts gives the same sentence once.
    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      isLink: true,
      onTap: _launch,
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
                ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                : (widget.isDark
                      ? WpColorsDark.hoverTransparent
                      : WpColorsLight.hoverTransparent),
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: WpIconSize.sm,
                color: widget.isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
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
                  style: TextStyle(
                    color: widget.isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                    fontSize: WpTypography.small,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Icon(
                LucideIcons.externalLink,
                size: WpIconSize.xs,
                color: widget.isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
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
  const _CopyDiagnosticsButton({required this.isDark});
  final bool isDark;

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
    // No `label:` — the rendered text is the accessible name, so the "Kopiert!"
    // confirmation now reaches a screen reader too. The hardcoded label used to
    // pin the announcement to "Debug-Infos kopieren" forever, which meant the
    // one bit of feedback this button gives was sighted-users-only.
    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text (see _AboutTapTarget)
    return _AboutTapTarget(
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: widget.isDark
              ? WpColorsDark.surfaceVariant
              : WpColorsLight.surfaceVariant,
          borderRadius: WpRadius.borderSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              SizedBox(
                width: WpIconSize.sm,
                height: WpIconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.isDark
                      ? WpColorsDark.textSecondary
                      : WpColorsLight.textSecondary,
                ),
              )
            else
              Icon(
                _copied ? LucideIcons.checkCheck : LucideIcons.copy,
                size: WpIconSize.sm,
                color: _copied
                    ? (widget.isDark
                          ? WpColorsDark.success
                          : WpColorsLight.success)
                    : (widget.isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary),
              ),
            const SizedBox(width: WpSpacing.xs),
            Text(
              _copied ? l10n.aboutCopied : l10n.aboutCopyDebugInfo,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w500,
                color: _copied
                    ? (widget.isDark
                          ? WpColorsDark.success
                          : WpColorsLight.success)
                    : (widget.isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
