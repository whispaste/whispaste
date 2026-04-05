import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Recording FAB — clean gradient, smooth pulse, no glow.
///
/// Gradient accent fill when idle, solid red when recording.
/// Scale animation on recording — subtle and premium.
class WpRecordingFab extends StatefulWidget {
  const WpRecordingFab({
    super.key,
    required this.isRecording,
    required this.onPressed,
  });

  final bool isRecording;
  final VoidCallback onPressed;

  @override
  State<WpRecordingFab> createState() => _WpRecordingFabState();
}

class _WpRecordingFabState extends State<WpRecordingFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnim;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(WpRecordingFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final recordLabel = widget.isRecording
        ? l10n.tooltipStopRecord
        : l10n.tooltipRecord;

    final gradient = widget.isRecording
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
          )
        : (isDark
            ? WpColorsDark.accentWarmGradient
            : WpColorsLight.accentWarmGradient);

    return Semantics(
      label: recordLabel,
      button: true,
      child: Tooltip(
        message: recordLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (context, child) {
              final scale = widget.isRecording
                  ? _scaleAnim.value
                  : _isHovered
                      ? 1.06
                      : 1.0;
              return AnimatedScale(
                scale: widget.isRecording ? scale : (_isHovered ? 1.06 : 1.0),
                duration: WpMotion.fast,
                child: child,
              );
            },
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: WpLayout.fabSize,
                height: WpLayout.fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  boxShadow: WpShadows.fab,
                ),
                child: Icon(
                  widget.isRecording ? LucideIcons.square : LucideIcons.mic,
                  color: Colors.white,
                  size: WpIconSize.lg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
