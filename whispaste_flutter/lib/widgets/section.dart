import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Flat content section with header and optional divider.
///
/// Used for settings groups and content sections — NOT a card.
/// Content sits directly on the dark surface.
class WpSection extends StatelessWidget {
  const WpSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: WpSpacing.lg,
      vertical: WpSpacing.md,
    ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.headerStyle,
    required this.colorScheme,
    this.onTap,
    this.isExpanded,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final TextStyle headerStyle;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;
  final bool? isExpanded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: WpRadius.borderSm,
      child: Row(
        children: [
          // Accent dot
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(right: WpSpacing.xs),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: headerStyle),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ?trailing,
          if (isExpanded != null)
            AnimatedRotation(
              turns: isExpanded! ? 0.5 : 0,
              duration: WpMotion.normal,
              child: Icon(
                Icons.keyboard_arrow_down,
                color: colorScheme.secondary,
                size: 20,
              ),
            ),
        ],
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

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: widget.trailing,
            headerStyle: widget.headerStyle,
            colorScheme: widget.colorScheme,
            isExpanded: _isExpanded,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.only(top: WpSpacing.md),
              child: widget.child,
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: WpMotion.smooth,
          ),
        ],
      ),
    );
  }
}
