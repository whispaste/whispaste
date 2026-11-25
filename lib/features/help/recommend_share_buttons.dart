/// One click to recommend WhisPaste on the user's own channels (#2185).
///
/// Shared by Help › Support and the rating dialog, so both offer the same
/// channels in the same order. Every button opens the network's public
/// web intent with the text prefilled (no SDK, no account access); YouTube
/// and every network without an intent get a ready text to paste. The link
/// carries the channel as campaign marker ([withShareCampaign]); nothing the
/// user dictated is ever part of it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/support/support_share_links.dart';
import '../../widgets/external_link.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_copy_feedback.dart';
import '../../widgets/wp_text_field.dart';

/// SharedPreferences key of the Mastodon instance the user shares to. Only
/// the host name, stored on this device.
const String kShareMastodonInstanceKey = 'share_mastodon_instance';

/// Order of the intent buttons: the networks people most often post links
/// to first, private channels (messengers, e-mail) last.
const List<SupportShareTarget> kRecommendShareOrder = [
  SupportShareTarget.x,
  SupportShareTarget.linkedin,
  SupportShareTarget.bluesky,
  SupportShareTarget.mastodon,
  SupportShareTarget.reddit,
  SupportShareTarget.facebook,
  SupportShareTarget.whatsapp,
  SupportShareTarget.telegram,
  SupportShareTarget.email,
];

/// Channel id of the "text for a video description" button.
const String kShareChannelYouTube = 'youtube';

/// Channel id of the "copy text and link" button.
const String kShareChannelCopy = 'copy';

/// The share buttons. [baseUrl] is the page to recommend (website or store
/// listing), [languageCode] the app language for the website campaign,
/// [onShared] gets the channel id of every share for the caller's own
/// telemetry and bookkeeping.
class RecommendShareButtons extends ConsumerStatefulWidget {
  const RecommendShareButtons({
    super.key,
    required this.baseUrl,
    required this.languageCode,
    required this.testIdPrefix,
    required this.onShared,
  });

  final String baseUrl;
  final String languageCode;
  final String testIdPrefix;
  final ValueChanged<String> onShared;

  @override
  ConsumerState<RecommendShareButtons> createState() =>
      _RecommendShareButtonsState();
}

class _RecommendShareButtonsState extends ConsumerState<RecommendShareButtons> {
  final _mastodonField = TextEditingController();
  bool _askMastodon = false;
  bool _mastodonInvalid = false;

  @override
  void dispose() {
    _mastodonField.dispose();
    super.dispose();
  }

  String _link(String channel) => withShareCampaign(
    widget.baseUrl,
    channel: channel,
    languageCode: widget.languageCode,
  );

  static String _label(L10n l10n, SupportShareTarget target) =>
      switch (target) {
        SupportShareTarget.x => 'X',
        SupportShareTarget.facebook => 'Facebook',
        SupportShareTarget.whatsapp => 'WhatsApp',
        SupportShareTarget.linkedin => 'LinkedIn',
        SupportShareTarget.reddit => 'Reddit',
        SupportShareTarget.telegram => 'Telegram',
        SupportShareTarget.bluesky => 'Bluesky',
        SupportShareTarget.mastodon => 'Mastodon',
        SupportShareTarget.email => l10n.supportShareEmail,
      };

  Future<void> _share(SupportShareTarget target, {String? instance}) async {
    final l10n = L10n.of(context);
    if (target == SupportShareTarget.mastodon && instance == null) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kShareMastodonInstanceKey);
      final host = saved == null ? null : mastodonInstanceHost(saved);
      if (host == null) {
        if (mounted) setState(() => _askMastodon = true);
        return;
      }
      instance = host;
    }
    if (!mounted) return;
    final uri = buildSupportShareUri(
      target,
      text: l10n.supportShareText,
      url: _link(target.name),
      mastodonInstance: instance,
    );
    widget.onShared(target.name);
    await openExternalUrl(context, uri.toString());
  }

  Future<void> _submitMastodon() async {
    final host = mastodonInstanceHost(_mastodonField.text);
    if (host == null) {
      setState(() => _mastodonInvalid = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kShareMastodonInstanceKey, host);
    if (!mounted) return;
    setState(() {
      _askMastodon = false;
      _mastodonInvalid = false;
    });
    await _share(SupportShareTarget.mastodon, instance: host);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final prefix = widget.testIdPrefix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: WpSpacing.buttonGap,
          runSpacing: WpSpacing.xs,
          children: [
            for (final target in kRecommendShareOrder)
              WpButton(
                key: ValueKey('$prefix-${target.name}'),
                testId: '$prefix-${target.name}',
                label: _label(l10n, target),
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                size: WpButtonSize.dense,
                opensExternally: true,
                onPressed: () => unawaited(_share(target)),
              ),
            WpCopyButton(
              testId: '$prefix-$kShareChannelYouTube',
              label: l10n.shareYouTubeCopy,
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.neutral,
              size: WpButtonSize.dense,
              text: () =>
                  '${l10n.shareYouTubeText} ${_link(kShareChannelYouTube)}',
              onCopied: () => widget.onShared(kShareChannelYouTube),
            ),
            WpCopyButton(
              testId: '$prefix-$kShareChannelCopy',
              label: l10n.shareCopyTextLink,
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.neutral,
              size: WpButtonSize.dense,
              text: () =>
                  '${l10n.supportShareText} ${_link(kShareChannelCopy)}',
              onCopied: () => widget.onShared(kShareChannelCopy),
            ),
          ],
        ),
        if (_askMastodon) ...[
          const SizedBox(height: WpSpacing.sm),
          Text(l10n.shareMastodonInstanceLabel, style: WpTextStyles.rowNote),
          const SizedBox(height: WpSpacing.xs),
          Row(
            children: [
              Expanded(
                child: WpTextField(
                  controller: _mastodonField,
                  variant: WpTextFieldVariant.form,
                  testId: '$prefix-mastodon-instance',
                  hintText: 'mastodon.social',
                  semanticsLabel: l10n.shareMastodonInstanceLabel,
                  autofocus: true,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => unawaited(_submitMastodon()),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              WpButton(
                testId: '$prefix-mastodon-go',
                label: l10n.shareMastodonGo,
                variant: WpButtonVariant.secondary,
                onPressed: () => unawaited(_submitMastodon()),
              ),
            ],
          ),
          if (_mastodonInvalid) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(l10n.shareMastodonInvalid, style: WpTextStyles.rowNote),
          ],
        ],
      ],
    );
  }
}
