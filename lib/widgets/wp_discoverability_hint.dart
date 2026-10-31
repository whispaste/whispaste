/// WpDiscoverabilityHint — a dezent, dismissible, one-time hint that surfaces
/// an otherwise-invisible text command (a voice-note prefix, a search
/// operator, …) next to the input field it belongs to.
///
/// Shown by default until the user dismisses it once; from then on the
/// "seen" flag is persisted via [SharedPreferences] (same idiom already used
/// by `store_thank_you_service.dart` / `recent_searches.dart`) and the hint
/// never reappears for that [hintId] — even across app restarts.
///
/// Reused identically at every call site (voice-notes input, history search
/// field, …) so every discoverability hint in the app feels the same; only
/// [hintId] (the persistence key) and [text] (the copy) differ per site.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

final _log = AppLogger('DiscoverabilityHint');

const _kHintSeenPrefKeyPrefix = 'discoverability_hint_seen_';

class WpDiscoverabilityHint extends StatefulWidget {
  const WpDiscoverabilityHint({
    super.key,
    required this.hintId,
    required this.text,
  });

  /// Unique persistence key — one "seen" flag per distinct hint.
  final String hintId;

  /// The discoverability copy. Should name the concrete prefix/operator
  /// rather than a vague nudge.
  final String text;

  @override
  State<WpDiscoverabilityHint> createState() => _WpDiscoverabilityHintState();
}

class _WpDiscoverabilityHintState extends State<WpDiscoverabilityHint> {
  // `null` while the persisted flag hasn't loaded yet — renders nothing to
  // avoid a one-frame flash before the real (possibly "seen") state is known.
  bool? _seen;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_prefKey) ?? false;
      if (mounted) setState(() => _seen = seen);
    } on Exception catch (e) {
      // No prefs plugin registered (e.g. golden/screenshot harnesses that
      // never mock it) — fail closed: never show the hint rather than crash
      // the page it's embedded in.
      _log.debug('Failed to load hint-seen flag (non-fatal): $e');
      if (mounted) setState(() => _seen = true);
    }
  }

  String get _prefKey => '$_kHintSeenPrefKeyPrefix${widget.hintId}';

  Future<void> _dismiss() async {
    setState(() => _seen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } on Exception catch (e) {
      // Non-fatal — the flag just won't persist this run.
      _log.debug('Failed to persist hint-seen flag (non-fatal): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_seen != false) return const SizedBox.shrink();

    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;

    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.lightbulb, size: WpIconSize.xs, color: accent),
          const SizedBox(width: WpSpacing.xxs),
          Expanded(
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: WpTypography.caption,
                color: textMuted,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.xxs),
          Semantics(
            label: L10n.of(context).hintDismiss,
            button: true,
            child: Tooltip(
              message: L10n.of(context).hintDismiss,
              child: WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadius.sm,
                child: InkWell(
                  onTap: _dismiss,
                  focusNode: _focusNode,
                  borderRadius: WpRadius.borderSm,
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: const Padding(
                    padding: EdgeInsets.all(WpSpacing.xxs),
                    child: Icon(
                      LucideIcons.x,
                      size: WpIconSize.xs,
                      color: textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
