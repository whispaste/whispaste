import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/app_info.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/page_shell.dart';

/// Supabase URL — injected at build time via `--dart-define`.
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);

/// Supabase anon key — injected at build time via `--dart-define`.
/// Public key, safe for client-side use (RLS enforces access control).
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
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

/// Thrown by [_FeedbackPageState._post] for HTTP responses that should not
/// be retried (rate-limited, server error).
class _ServerException implements Exception {
  final String code; // 'rate_limited' | 'server_error'
  const _ServerException(this.code);
}

/// Feedback page — polished, chat-inspired feedback form.
///
/// Top-aligned, responsive: narrow form column on wide screens with generous
/// padding so it breathes on maximized desktop windows.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

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
                      _error == 'rate_limited'
                          ? l10n.feedbackErrorRateLimited
                          : _error == 'network_error'
                              ? l10n.feedbackErrorNetwork
                              : l10n.feedbackErrorServer,
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
                        onPressed:
                            _canSubmit && !_submitting ? _submit : null,
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

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
        _log.info(
          'Supabase not configured — skipping feedback submission '
          '(rating=$_rating category=$_category)',
        );
      } else {
        _log.info('Submitting feedback: rating=$_rating category=$_category');
        final payload = {
          'rating': _rating,
          'feedback_text': _commentController.text.trim(),
          'category': _category,
          'app_version': appVersion,
          'device_id_hash': _deriveDeviceId(),
        };
        await _post(payload);
        _log.info('Feedback submitted successfully');
      }
      if (mounted) setState(() => _submitted = true);
    } on _ServerException catch (e) {
      if (mounted) setState(() { _submitting = false; _error = e.code; });
    } on Exception catch (e) {
      _log.warning('Feedback submission failed: $e');
      if (mounted) setState(() { _submitting = false; _error = 'network_error'; });
    }
  }

  /// Sends the feedback payload to Supabase via a direct PostgREST INSERT.
  ///
  /// No automatic retry — the form is manual and retrying a timed-out POST
  /// could create a duplicate row. Users can re-submit on error.
  ///
  /// Throws [_ServerException] for rate-limit and server-error responses.
  /// Throws the underlying [Exception] (e.g. [SocketException]) for network
  /// failures.
  Future<void> _post(Map<String, Object?> payload) async {
    final response = await http
        .post(
          Uri.parse('$_supabaseUrl/rest/v1/user_feedback'),
          headers: {
            'Content-Type': 'application/json',
            'apikey': _supabaseAnonKey,
            'Authorization': 'Bearer $_supabaseAnonKey',
            'Prefer': 'return=minimal',
            'User-Agent': appUserAgent,
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      _log.info('Feedback rate-limited (429)');
      throw const _ServerException('rate_limited');
    }
    // PG trigger raises P0001 → PostgREST returns 400 with "rate_limited".
    if (response.statusCode == 400 && response.body.contains('rate_limited')) {
      _log.info('Feedback rate-limited by DB trigger');
      throw const _ServerException('rate_limited');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.warning(
        'Feedback submission error: ${response.statusCode} ${response.body}',
      );
      throw const _ServerException('server_error');
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
