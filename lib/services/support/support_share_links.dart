/// Share links for recommending WhisPaste.
///
/// Each target uses the network's public web-intent endpoint, so no share SDK
/// is needed. Query values are percent-encoded by [Uri]; the caller only
/// supplies the already localized text. Instagram, YouTube and TikTok have no
/// link-share intent and are intentionally absent; the share buttons offer
/// the text for a video description and "copy text and link" for them.
/// Mastodon has no central intent: it needs the user's own instance
/// ([mastodonInstanceHost]).
///
/// Shared links carry a campaign marker for the channel (#2185), so the
/// website's Matomo and the store reports can tell app shares apart; the
/// marker names only the channel, never text or a person.
library;

import '../../core/app_urls.dart';

enum SupportShareTarget {
  x,
  facebook,
  whatsapp,
  linkedin,
  reddit,
  telegram,
  bluesky,
  mastodon,
  email,
}

/// Campaign name of a share from the app through [channel] (`x`, `email`,
/// `youtube`, `copy`, ...). Same scheme as the website's own campaigns:
/// lower case, hyphens.
String shareCampaign(String channel) => 'app-share-$channel';

/// [url] with the campaign marker of [channel]: the store listings get their
/// store's campaign parameter (Partner Center `cid`, App Store Connect `ct`),
/// the website the Matomo campaign with the page language as keyword
/// ([languageCode]). Any other link stays as it is.
String withShareCampaign(
  String url, {
  required String channel,
  required String languageCode,
}) {
  final uri = Uri.parse(url);
  final campaign = shareCampaign(channel);
  // Hosts come from app_urls.dart, the one source of the store URLs.
  final host = uri.host;
  final extra = host == Uri.parse(kMicrosoftStoreListingUrl).host
      ? {'cid': campaign}
      : host == Uri.parse(kMacAppStoreListingUrl).host
      ? {'ct': campaign}
      : host == Uri.parse(kWebsiteUrl).host
      ? {'mtm_campaign': campaign, 'mtm_kwd': languageCode}
      : const <String, String>{};
  if (extra.isEmpty) return url;
  return uri
      .replace(queryParameters: {...uri.queryParameters, ...extra})
      .toString();
}

/// The host of a Mastodon instance as people write it: `mastodon.social`,
/// `https://chaos.social/`, `@me@troet.cafe`. Null when it is no host name.
String? mastodonInstanceHost(String input) {
  var text = input.trim().toLowerCase();
  if (text.isEmpty) return null;
  // A profile URL (https://host/@name) keeps only its host.
  text = text.replaceFirst(RegExp(r'^[a-z]+://'), '');
  final slash = text.indexOf('/');
  if (slash >= 0) text = text.substring(0, slash);
  // A handle (@name@host) names its instance after the last @.
  final at = text.lastIndexOf('@');
  if (at >= 0) text = text.substring(at + 1);
  final host = RegExp(
    r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
  );
  return host.hasMatch(text) ? text : null;
}

/// Builds the web-intent URI for [target].
///
/// [text] is the localized recommendation without the link; [url] is appended
/// or passed as the link parameter depending on what the target supports.
/// [subject] is used only for [SupportShareTarget.email], [mastodonInstance]
/// (a host from [mastodonInstanceHost]) only for
/// [SupportShareTarget.mastodon], which falls back to `mastodon.social`.
Uri buildSupportShareUri(
  SupportShareTarget target, {
  required String text,
  String url = kWebsiteUrl,
  String subject = 'WhisPaste',
  String? mastodonInstance,
}) {
  final message = '$text $url';
  return switch (target) {
    SupportShareTarget.x => Uri.https('twitter.com', '/intent/tweet', {
      'text': text,
      'url': url,
    }),
    SupportShareTarget.facebook => Uri.https(
      'www.facebook.com',
      '/sharer/sharer.php',
      {'u': url},
    ),
    SupportShareTarget.whatsapp => Uri.https('wa.me', '/', {'text': message}),
    SupportShareTarget.linkedin => Uri.https(
      'www.linkedin.com',
      '/sharing/share-offsite/',
      {'url': url},
    ),
    SupportShareTarget.reddit => Uri.https('www.reddit.com', '/submit', {
      'url': url,
      'title': text,
    }),
    SupportShareTarget.telegram => Uri.https('t.me', '/share/url', {
      'url': url,
      'text': text,
    }),
    SupportShareTarget.bluesky => Uri.https('bsky.app', '/intent/compose', {
      'text': message,
    }),
    SupportShareTarget.mastodon => Uri.https(
      mastodonInstance ?? 'mastodon.social',
      '/share',
      {'text': message},
    ),
    // mailto bodies need %20/%0A, not the form-encoded '+' that Uri.https
    // writes for queries, so the query string is encoded by hand.
    SupportShareTarget.email => Uri(
      scheme: 'mailto',
      query:
          'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(message)}',
    ),
  };
}
