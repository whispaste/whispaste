import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Content section with header — flat, clean, with optional collapse.
///
/// Premium: subtle accent line on header, refined typography, smooth expand.
///
/// [padding] defaults to zero because the page owns the inset, not the
/// section: every section in the app sits inside a [WpPageShell], whose
/// `fromLTRB(24, 12, 24, 24)` already supplies the horizontal gutter. The
/// default used to be `symmetric(horizontal: 24, vertical: 16)` — an inset
/// *on top of* the shell's — which is why all 20 call sites (16 settings
/// sections, About, 3 analytics cards) passed `EdgeInsets.zero` to cancel it.
/// A default no caller wants is not a default, it is a trap: the 21st section
/// that forgets the override would silently indent 24 px further than its
/// siblings and gain 16 px of vertical air, which is exactly the kind of
/// unexplained spacing drift this component exists to prevent. Zero is what
/// the app actually renders today, so making it the default changes no pixel
/// and makes the quiet path the correct one.
class WpSection extends StatelessWidget {
  const WpSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final bool collapsible;
  final bool initiallyExpanded;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.headlineMedium!;

    if (collapsible) {
      return _CollapsibleSection(
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        headerStyle: headerStyle,
        colorScheme: cs,
        initiallyExpanded: initiallyExpanded,
        padding: padding,
        child: child,
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            headerStyle: headerStyle,
            colorScheme: cs,
          ),
          const SizedBox(height: WpSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Accent-bar geometry, split out because the *sum* is the load-bearing part.
///
/// A settings section used to present four competing left edges: 0 (accent
/// bar and row hover surface), 15 (section title), 12 (row icon) and 40 (row
/// label). 15-against-12 was the worst of them — near enough to look like a
/// mistake, far enough to see. `settings_widgets.dart` exports
/// `kSettingRowInset` (12) as the app's shared reading edge, and
/// `onboarding_headings.dart` deliberately pins its headings to it; only the
/// section head that sits directly above those rows ignored it.
///
/// 3 + 9 = 12 puts the title text on exactly that edge, so the bar hangs in
/// the gutter as decoration and everything that carries meaning — section
/// title, row icon — starts on one line. Two edges instead of four.
///
/// Off the spacing scale on purpose: the constraint is the sum, not the gap,
/// and `WpSpacing.sm` (12) for the gutter is what produced the 15 in the first
/// place. Not imported from `settings_widgets.dart` — a shared widget must not
/// depend on a feature — so the number is restated here with its reason, and
/// `section_test.dart` pins it so the two cannot drift apart silently.
const double _accentBarWidth = 3;
const double _accentBarGutter = 9;

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.headerStyle,
    required this.colorScheme,
    this.onTap,
    this.isExpanded,
    this.focusNode,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final TextStyle headerStyle;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;
  final bool? isExpanded;

  /// When non-null, [WpFocusRing] is applied and this node is shared with the
  /// inner [InkWell] for keyboard activation (Enter/Space).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final inkWell = InkWell(
      onTap: onTap,
      focusNode: focusNode,
      borderRadius: WpRadius.borderSm,
      // WpFocusRing owns focus visuals when focusNode is provided.
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
        child: Row(
          children: [
            // Accent bar — warm gradient vertical line
            Container(
              width: _accentBarWidth,
              height: 18,
              margin: const EdgeInsets.only(right: _accentBarGutter),
              decoration: BoxDecoration(
                gradient: WpColors.accentWarmGradient,
                borderRadius: WpRadius.borderFull,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: headerStyle),
                  if (subtitle != null)
                    Padding(
                      // 2px title-subtitle gap: tighter than WpSpacing.xxs so
                      // the pair reads as one unit.
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (isExpanded != null)
              AnimatedRotation(
                turns: isExpanded! ? 0.5 : 0,
                duration: WpMotion.durationFor(context, WpMotion.normal),
                child: Icon(
                  LucideIcons.chevronDown,
                  color: colorScheme.secondary,
                  size: WpIconSize.sm,
                ),
              ),
          ],
        ),
      ),
    );

    // House idiom for a composed control (see `mic_permission_chip.dart`):
    // MergeSemantics + a *label-less* Semantics. A `label:` here would not
    // replace the subtree's own text, it would be prepended to it — the
    // rendered `Text(title)` still contributes a node, so a screen reader
    // read the title twice ("Title, Title, Subtitle") on all ~20 call sites
    // of this header. Verified against the framework, not assumed.
    //
    // `header: true` rather than `button:` alone: this *is* the section
    // heading, so it should show up in a screen reader's heading rotor even
    // when it is not collapsible. `expanded` is set only for the collapsible
    // variant, where it is the one piece of state the visual chevron carries
    // and the semantics tree previously did not.
    return MergeSemantics(
      child: Semantics(
        header: true,
        button: onTap != null,
        expanded: isExpanded,
        child: focusNode != null
            ? WpFocusRing(
                focusNode: focusNode,
                radius: WpRadius.sm,
                child: inkWell,
              )
            : inkWell,
      ),
    );
  }
}

class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.headerStyle,
    required this.colorScheme,
    required this.initiallyExpanded,
    required this.padding,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final TextStyle headerStyle;
  final ColorScheme colorScheme;
  final bool initiallyExpanded;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late final AnimationController _controller;
  late final Animation<double> _heightFactor;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      // Placeholder — didChangeDependencies immediately below overwrites this
      // with the reduced-motion-aware value before context is safe to read.
      duration: WpMotion.smooth,
      value: _isExpanded ? 1.0 : 0.0,
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route collapse animation through the reduced-motion guard.
    _controller.duration = WpMotion.durationFor(context, WpMotion.smooth);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // loam-ignore: a11y-interactive-semantics – semantics provided in _SectionHeader.build
          _SectionHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: widget.trailing,
            headerStyle: widget.headerStyle,
            colorScheme: widget.colorScheme,
            isExpanded: _isExpanded,
            onTap: _toggle,
            focusNode: _focusNode,
          ),
          ClipRect(
            child: AnimatedBuilder(
              animation: _heightFactor,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.topLeft,
                  heightFactor: _heightFactor.value,
                  child: Opacity(opacity: _heightFactor.value, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(top: WpSpacing.md),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
