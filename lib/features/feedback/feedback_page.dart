import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/app_info.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/feedback_submission_service.dart';
import '../../widgets/page_shell.dart';

/// Supabase URL — injected at build time via `--dart-define`.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');

/// Supabase publishable key — injected at build time via `--dart-define`.
/// Public key (replaces legacy anon key), safe for client-side use.
/// RLS enforces all access control server-side.
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Computes a stable 12-character hex device identifier hash from [hostname].
///
/// The result is always exactly 12 lowercase hex characters — matching the
/// `length(device_id_hash) = 12` constraint in the RLS policy.
/// Exposed via [visibleForTesting] so unit tests can verify the hash logic
/// without going through the full widget submit flow.
@visibleForTesting
String computeFeedbackDeviceIdHash(String hostname) {
  final bytes = utf8.encode('${hostname}_whispaste');
  return md5.convert(bytes).toString().substring(0, 12);
}

const _kLastFeedbackKey = 'feedback_last_submitted_ms';
const _kClientRateLimitHours = 24;

/// Returns true if the user has submitted feedback within the last 24 hours.
/// Prevents unnecessary network calls before the server-side check.
Future<bool> _isClientRateLimited() async {
  final prefs = await SharedPreferences.getInstance();
  final lastMs = prefs.getInt(_kLastFeedbackKey);
  if (lastMs == null) return false;
  final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
  return elapsed < const Duration(hours: _kClientRateLimitHours).inMilliseconds;
}

Future<void> _recordFeedbackSubmission() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastFeedbackKey, DateTime.now().millisecondsSinceEpoch);
}

/// Feedback page — polished, chat-inspired feedback form.
///
/// Top-aligned, responsive: narrow form column on wide screens with generous
/// padding so it breathes on maximized desktop windows.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this._submissionService});

  final FeedbackSubmissionService? _submissionService;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static final _log = AppLogger('FeedbackPage');

  int _rating = 0;
  String _category = '';
  final _commentController = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  late final FeedbackSubmissionService _service;

  @override
  void initState() {
    super.initState();
    _service =
        widget._submissionService ??
        FeedbackSubmissionService(
          client: http.Client(),
          supabaseUrl: _supabaseUrl,
          supabasePublishableKey: _supabasePublishableKey,
        );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _rating > 0 && _category.isNotEmpty && _commentController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = Theme.of(context).textTheme;
    final l10n = L10n.of(context);

    if (_submitted) {
      return WpPageShell(
        child: _ThankYouView(isDark: isDark, ts: ts, onReset: _reset),
      );
    }

    return WpPageShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Constrain form width on wide screens for readability
          final maxFormWidth = constraints.maxWidth > 720
              ? 560.0
              : double.infinity;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: WpSpacing.lg),

                  // Title area
                  Text(l10n.feedbackTitle, style: ts.headlineMedium),
                  const SizedBox(height: WpSpacing.xs),
                  Text(
                    l10n.feedbackSubtitle,
                    style: ts.bodyMedium?.copyWith(
                      color: isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary,
                    ),
                  ),

                  const SizedBox(height: WpSpacing.xxxl),

                  // Category selection
                  Text(l10n.feedbackCategoryLabel, style: ts.titleSmall),
                  const SizedBox(height: WpSpacing.md),
                  Wrap(
                    spacing: WpSpacing.sm,
                    runSpacing: WpSpacing.sm,
                    children: [
                      _CategoryChip(
                        icon: LucideIcons.bug,
                        label: l10n.feedbackCategoryBug,
                        value: 'bug',
                        selected: _category,
                        isDark: isDark,
                        onTap: (v) => setState(() => _category = v),
                      ),
                      _CategoryChip(
                        icon: LucideIcons.lightbulb,
                        label: l10n.feedbackCategoryFeature,
                        value: 'feature',
                        selected: _category,
                        isDark: isDark,
                        onTap: (v) => setState(() => _category = v),
                      ),
                      _CategoryChip(
                        icon: LucideIcons.messageCircle,
                        label: l10n.feedbackCategoryGeneral,
                        value: 'general',
                        selected: _category,
                        isDark: isDark,
                        onTap: (v) => setState(() => _category = v),
                      ),
                      _CategoryChip(
                        icon: LucideIcons.sparkles,
                        label: l10n.feedbackCategoryAiQuality,
                        value: 'ai',
                        selected: _category,
                        isDark: isDark,
                        onTap: (v) => setState(() => _category = v),
                      ),
                    ],
                  ),

                  const SizedBox(height: WpSpacing.xxxl),

                  // Emoji rating
                  Text(l10n.feedbackRatingLabel, style: ts.titleSmall),
                  const SizedBox(height: WpSpacing.md),
                  _EmojiRatingRow(
                    rating: _rating,
                    isDark: isDark,
                    onChanged: (v) => setState(() => _rating = v),
                  ),

                  const SizedBox(height: WpSpacing.xxxl),

                  // Comment field — chat-styled
                  Text(l10n.feedbackCommentsLabel, style: ts.titleSmall),
                  const SizedBox(height: WpSpacing.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? WpColorsDark.warmSurfaceGradient
                          : WpColorsLight.warmSurfaceGradient,
                      borderRadius: WpRadius.borderMd,
                      border: Border.all(
                        color: isDark
                            ? WpColorsDark.borderDefault
                            : WpColorsLight.borderDefault,
                      ),
                    ),
                    child: TextField(
                      controller: _commentController,
                      maxLines: 5,
                      maxLength: 1000,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _category == 'bug'
                            ? l10n.feedbackPlaceholderBug
                            : _category == 'feature'
                            ? l10n.feedbackPlaceholderFeature
                            : _category == 'ai'
                            ? l10n.feedbackPlaceholderAi
                            : l10n.feedbackPlaceholderGeneral,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(WpSpacing.md),
                      ),
                    ),
                  ),

                  const SizedBox(height: WpSpacing.xxl),

                  // Error message
                  if (_error != null) ...[
                    Text(
                      _errorText(l10n),
                      style: ts.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: WpSpacing.sm),
                  ],

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedOpacity(
                      duration: WpMotion.fast,
                      opacity: _canSubmit && !_submitting ? 1.0 : 0.5,
                      child: ElevatedButton.icon(
                        onPressed: _canSubmit && !_submitting ? _submit : null,
                        icon: _submitting
                            ? const SizedBox(
                                width: WpIconSize.sm,
                                height: WpIconSize.sm,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.send, size: WpIconSize.sm),
                        label: Text(
                          _submitting
                              ? l10n.feedbackSubmitting
                              : l10n.feedbackSubmit,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: WpSpacing.md,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: WpSpacing.lg),

                  // Privacy note
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.lock,
                          size: WpIconSize.xs,
                          color: isDark
                              ? WpColorsDark.textMuted
                              : WpColorsLight.textMuted,
                        ),
                        const SizedBox(width: WpSpacing.xxs),
                        Text(
                          l10n.feedbackPrivacyNote,
                          style: ts.bodySmall?.copyWith(
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: WpSpacing.xxxl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _errorText(L10n l10n) {
    return switch (_error) {
      'rate_limited' => l10n.feedbackErrorRateLimited,
      'network_error' => l10n.feedbackErrorNetwork,
      'not_configured' => l10n.feedbackErrorNotConfigured,
      _ => l10n.feedbackErrorServer,
    };
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Capture locale before the first await to avoid using BuildContext across
    // an async gap (lint: use_build_context_synchronously).
    final locale = Localizations.localeOf(context).languageCode;

    try {
      // Client-side rate limit check — avoids unnecessary network round-trips.
      if (await _isClientRateLimited()) {
        _log.info('Feedback blocked by client-side rate limit (24h cooldown)');
        if (mounted) {
          setState(() {
            _submitting = false;
            _error = 'rate_limited';
          });
        }
        return;
      }

      final payload = FeedbackPayload(
        rating: _rating,
        feedbackText: _commentController.text.trim(),
        category: _category,
        appVersion: appVersion,
        deviceIdHash: _deriveDeviceId(),
        locale: locale,
      );

      final result = await _service.submit(payload);

      if (!mounted) return;

      switch (result) {
        case FeedbackSent():
          await _recordFeedbackSubmission();
          setState(() => _submitted = true);
        case FeedbackSkippedNotConfigured():
          setState(() {
            _submitting = false;
            _error = 'not_configured';
          });
        case FeedbackRateLimitedServer():
          setState(() {
            _submitting = false;
            _error = 'rate_limited';
          });
        case FeedbackServerError():
          setState(() {
            _submitting = false;
            _error = 'server_error';
          });
        case FeedbackNetworkError():
          setState(() {
            _submitting = false;
            _error = 'network_error';
          });
      }
    } on Exception catch (e) {
      _log.warning('Feedback submission failed unexpectedly: $e');
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'server_error';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _submitted = false;
      _submitting = false;
      _error = null;
      _rating = 0;
      _category = '';
      _commentController.clear();
    });
  }

  static String _deriveDeviceId() {
    try {
      return computeFeedbackDeviceIdHash(Platform.localHostname);
    } on Exception {
      return computeFeedbackDeviceIdHash('fallback_device');
    }
  }
}

// ---------------------------------------------------------------------------
// Thank-you state — shown after submission
// ---------------------------------------------------------------------------

class _ThankYouView extends StatelessWidget {
  const _ThankYouView({
    required this.isDark,
    required this.ts,
    required this.onReset,
  });

  final bool isDark;
  final TextTheme ts;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 720 ? 480.0 : double.infinity;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: WpSpacing.xxxl * 1.5),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: isDark
                        ? WpColorsDark.accentSubtle
                        : WpColorsLight.accentSubtle,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    LucideIcons.heart,
                    size: WpIconSize.xl,
                    color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxl),
                Text(l10n.feedbackThankYou, style: ts.headlineMedium),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.feedbackThankYouMessage,
                  textAlign: TextAlign.center,
                  style: ts.bodyMedium?.copyWith(
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxxl),
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(
                    LucideIcons.messageSquarePlus,
                    size: WpIconSize.sm,
                  ),
                  label: Text(l10n.feedbackSendAnother),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips — selectable feedback type
// ---------------------------------------------------------------------------

class _CategoryChip extends StatefulWidget {
  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String selected;
  final bool isDark;
  final ValueChanged<String> onTap;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.value == widget.selected;

    final Color bg;
    final Color fg;

    if (isActive) {
      bg = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_hovered) {
      bg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.value),
        child: AnimatedContainer(
          duration: _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderFull,
            border: isActive
                ? Border.all(
                    color:
                        (widget.isDark
                                ? WpColorsDark.accent
                                : WpColorsLight.accent)
                            .withValues(alpha: 0.3),
                  )
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: WpIconSize.sm, color: fg),
              const SizedBox(width: WpSpacing.xs),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji rating row — modern, chat-app-like rating
// ---------------------------------------------------------------------------

class _EmojiRatingRow extends StatelessWidget {
  const _EmojiRatingRow({
    required this.rating,
    required this.isDark,
    required this.onChanged,
  });

  final int rating;
  final bool isDark;
  final ValueChanged<int> onChanged;

  static const _emojis = ['😟', '😐', '🙂', '😊', '🤩'];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final labels = [
      l10n.feedbackRatingFrustrated,
      l10n.feedbackRatingMeh,
      l10n.feedbackRatingOkay,
      l10n.feedbackRatingHappy,
      l10n.feedbackRatingLoveIt,
    ];
    return Row(
      children: List.generate(5, (i) {
        final isSelected = rating == i + 1;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i + 1),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: WpMotion.fast,
                margin: EdgeInsets.only(right: i < 4 ? WpSpacing.xs : 0),
                padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                            ? WpColorsDark.accentSubtle
                            : WpColorsLight.accentSubtle)
                      : (isDark
                            ? WpColorsDark.surfaceVariant
                            : WpColorsLight.surfaceVariant),
                  borderRadius: WpRadius.borderMd,
                  border: isSelected
                      ? Border.all(
                          color:
                              (isDark
                                      ? WpColorsDark.accent
                                      : WpColorsLight.accent)
                                  .withValues(alpha: 0.4),
                        )
                      : Border.all(color: Colors.transparent),
                ),
                child: Column(
                  children: [
                    Text(
                      _emojis[i],
                      style: TextStyle(fontSize: isSelected ? 28 : 22),
                    ),
                    const SizedBox(height: WpSpacing.xxs),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? (isDark
                                  ? WpColorsDark.textPrimary
                                  : WpColorsLight.textPrimary)
                            : (isDark
                                  ? WpColorsDark.textMuted
                                  : WpColorsLight.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
