import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Content section with header — flat, clean, with optional collapse.
///
/// Premium: subtle accent line on header, refined typography, smooth expand.
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
      horizontal: WpSpacing.xl,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: WpRadius.borderSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
        child: Row(
          children: [
            // Accent bar — warm gradient vertical line
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(right: WpSpacing.sm),
              decoration: BoxDecoration(
                gradient: isDark
                    ? WpColorsDark.accentWarmGradient
                    : WpColorsLight.accentWarmGradient,
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
                duration: WpMotion.normal,
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

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: WpMotion.smooth,
      value: _isExpanded ? 1.0 : 0.0,
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void dispose() {
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
          _SectionHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: widget.trailing,
            headerStyle: widget.headerStyle,
            colorScheme: widget.colorScheme,
            isExpanded: _isExpanded,
            onTap: _toggle,
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
