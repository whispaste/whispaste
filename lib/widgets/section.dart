import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Content section with header — flat, clean, with optional collapse.
///
/// Deliberately paints **no surface of its own** (Ticket 08). "Card material on
/// the shared primitives" stops at the section head: a section is a grouping of
/// content, and several of its call sites already hand it children that *are*
/// cards (`analytics_page.dart` puts `WpTwoPanel` and the hero stats row inside
/// three sections). A fill here would card-in-a-card every one of them. Which
/// screens wrap section content in a card is a per-screen decision and belongs
/// to the screen tickets, not to this widget.
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
    this.testId,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Accessibility identifier of the section heading.
  final String? testId;
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
        testId: testId,
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
            testId: testId,
          ),
          const SizedBox(height: WpSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// The section title starts on the section's own edge, where the cards,
/// panels and paragraphs below it start too (Übersicht, Statistik, Handbuch).
/// It used to sit 12 px in to match the settings rows' inset, but settings
/// no longer use this widget, and the indent left every remaining caller with
/// a title that stood off its own content.

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
    this.testId,
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

  /// Accessibility identifier of the heading node.
  final String? testId;

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

    // House idiom for a composed control: MergeSemantics + a *label-less*
    // Semantics. A `label:` here would not
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
        identifier: testId,
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
    this.testId,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final TextStyle headerStyle;
  final ColorScheme colorScheme;
  final bool initiallyExpanded;
  final EdgeInsets padding;
  final Widget child;
  final String? testId;

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
            testId: widget.testId,
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
