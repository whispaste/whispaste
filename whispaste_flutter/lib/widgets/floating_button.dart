import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../features/recording/recording_state.dart';

// ---------------------------------------------------------------------------
// Floating button — always-on-top recording widget
// ---------------------------------------------------------------------------

/// A phase-aware floating recording button for the always-on-top overlay
/// window. Renders as a circle with gradient fill, phase-specific icon, and
/// pulse / spin animations. Supports drag, tap (toggle recording), and
/// long-press (context menu).
class WpFloatingButton extends ConsumerStatefulWidget {
  const WpFloatingButton({
    super.key,
    required this.size,
    required this.opacity,
    required this.phase,
    required this.onTap,
    required this.onLongPress,
    this.onNavigate,
    this.onHide,
    this.onQuit,
    this.locked = false,
  });

  /// Diameter in logical pixels (48, 56, or 72).
  final double size;

  /// Overall widget opacity (0.0–1.0).
  final double opacity;

  /// Current recording phase — drives gradient, icon, and animation.
  final RecordingPhase phase;

  /// Toggle recording (start / stop).
  final VoidCallback onTap;

  /// Show the long-press context menu.
  final VoidCallback onLongPress;

  /// Navigate to a named page (e.g. 'history', 'settings').
  final void Function(String page)? onNavigate;

  /// Hide the floating button window.
  final VoidCallback? onHide;

  /// Quit the application.
  final VoidCallback? onQuit;

  /// When true, dragging is disabled.
  final bool locked;

  @override
  ConsumerState<WpFloatingButton> createState() => _WpFloatingButtonState();
}

class _WpFloatingButtonState extends ConsumerState<WpFloatingButton>
    with TickerProviderStateMixin {
  // -- animation controllers ------------------------------------------------

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _spinController;

  bool _isHovered = false;

  // -- lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Pulse ring animation for recording state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Spin animation for transcribing state
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant WpFloatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) _syncAnimations();
  }

  void _syncAnimations() {
    if (widget.phase == RecordingPhase.recording) {
      _pulseController.repeat();
    } else {
      _pulseController
        ..stop()
        ..reset();
    }

    if (widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing) {
      _spinController.repeat();
    } else {
      _spinController
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  // -- long-press menu ------------------------------------------------------

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surfaceColor =
        isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated;
    final textColor =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final mutedColor =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    showMenu<_MenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: WpRadius.borderLg,
        side: BorderSide(
          color: isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle,
        ),
      ),
      items: [
        _menuItem(
          _MenuAction.dashboard,
          LucideIcons.layoutDashboard,
          l10n.navHistory,
          textColor,
          mutedColor,
        ),
        _menuItem(
          _MenuAction.settings,
          LucideIcons.settings,
          l10n.navSettings,
          textColor,
          mutedColor,
        ),
        _menuItem(
          _MenuAction.hide,
          LucideIcons.eyeOff,
          'Hide', // not yet in l10n
          textColor,
          mutedColor,
        ),
        _menuItem(
          _MenuAction.quit,
          LucideIcons.power,
          'Quit', // not yet in l10n
          textColor,
          mutedColor,
        ),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case _MenuAction.dashboard:
          widget.onNavigate?.call('history');
        case _MenuAction.settings:
          widget.onNavigate?.call('settings');
        case _MenuAction.hide:
          widget.onHide?.call();
        case _MenuAction.quit:
          widget.onQuit?.call();
      }
    });
  }

  static PopupMenuItem<_MenuAction> _menuItem(
    _MenuAction value,
    IconData icon,
    String label,
    Color textColor,
    Color iconColor,
  ) {
    return PopupMenuItem<_MenuAction>(
      value: value,
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: WpIconSize.sm, color: iconColor),
          const SizedBox(width: WpSpacing.sm),
          Text(label, style: TextStyle(color: textColor, fontSize: 13)),
        ],
      ),
    );
  }

  // -- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final phase = widget.phase;
    final size = widget.size;

    final isInteractive =
        phase == RecordingPhase.idle || phase == RecordingPhase.recording;

    final tooltip = switch (phase) {
      RecordingPhase.idle => l10n.tooltipRecord,
      RecordingPhase.recording => l10n.tooltipStopRecord,
      RecordingPhase.transcribing || RecordingPhase.processing => l10n.tooltipProcessing,
      RecordingPhase.done => l10n.statusTranscriptionDone,
      RecordingPhase.error => '',
    };

    final gradient = _gradient(phase, isDark);
    final iconData = _icon(phase);
    final iconSize = size * 0.42; // proportional to button size

    // Outer opacity wrapper
    return Opacity(
      opacity: widget.opacity.clamp(0.0, 1.0),
      child: SizedBox(
        // Extra space for the pulse ring
        width: size * 1.8,
        height: size * 1.8,
        child: Center(
          child: Semantics(
            label: tooltip,
            button: isInteractive,
            child: Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: isInteractive
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                    [_pulseController, _spinController],
                  ),
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulse ring (recording only)
                        if (phase == RecordingPhase.recording)
                          _buildPulseRing(size, gradient),

                        // Button
                        child!,
                      ],
                    );
                  },
                  child: GestureDetector(
                    onTap: isInteractive ? widget.onTap : null,
                    onLongPressStart: (details) {
                      widget.onLongPress();
                      _showContextMenu(context, details.globalPosition);
                    },
                    child: AnimatedScale(
                      scale: _isHovered && isInteractive ? 1.08 : 1.0,
                      duration: WpMotion.fast,
                      curve: Curves.easeOut,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: gradient,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: WpMotion.fast,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: phase == RecordingPhase.transcribing ||
                                    phase == RecordingPhase.processing
                                ? _buildSpinner(iconSize)
                                : Icon(
                                    iconData,
                                    key: ValueKey(phase),
                                    color: Colors.white,
                                    size: iconSize,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- sub-widgets ----------------------------------------------------------

  Widget _buildPulseRing(double buttonSize, LinearGradient gradient) {
    final ringSize = buttonSize * _pulseScale.value;
    final ringColor =
        (gradient.colors.first).withValues(alpha: _pulseOpacity.value);

    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.5),
      ),
    );
  }

  Widget _buildSpinner(double iconSize) {
    return AnimatedBuilder(
      animation: _spinController,
      builder: (context, child) => Transform.rotate(
        angle: _spinController.value * 2 * math.pi,
        child: child,
      ),
      child: Icon(
        LucideIcons.loaderCircle,
        key: const ValueKey(RecordingPhase.transcribing),
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  // -- helpers --------------------------------------------------------------

  static LinearGradient _gradient(RecordingPhase phase, bool isDark) {
    return switch (phase) {
      RecordingPhase.idle => isDark
          ? WpColorsDark.accentWarmGradient
          : WpColorsLight.accentWarmGradient,
      RecordingPhase.recording => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
      RecordingPhase.transcribing || RecordingPhase.processing => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        ),
      RecordingPhase.done => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
        ),
      RecordingPhase.error => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
        ),
    };
  }

  static IconData _icon(RecordingPhase phase) {
    return switch (phase) {
      RecordingPhase.idle => LucideIcons.mic,
      RecordingPhase.recording => LucideIcons.square,
      RecordingPhase.transcribing || RecordingPhase.processing => LucideIcons.loaderCircle,
      RecordingPhase.done => LucideIcons.check,
      RecordingPhase.error => LucideIcons.triangleAlert,
    };
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

enum _MenuAction { dashboard, settings, hide, quit }
