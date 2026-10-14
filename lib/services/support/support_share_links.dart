/// Share links for recommending WhisPaste.
///
/// Each target uses the network's public web-intent endpoint, so no share SDK
/// is needed. Query values are percent-encoded by [Uri]; the caller only
/// supplies the already localized text. Instagram, YouTube and TikTok have no
/// link-share intent and are intentionally absent.
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
  email,
}

/// Builds the web-intent URI for [target].
///
/// [text] is the localized recommendation without the link; [url] is appended
/// or passed as the link parameter depending on what the target supports.
/// [subject] is used only for [SupportShareTarget.email].
Uri buildSupportShareUri(
  SupportShareTarget target, {
  required String text,
  String url = kWebsiteUrl,
  String subject = 'WhisPaste',
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
