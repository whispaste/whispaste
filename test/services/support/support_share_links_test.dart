/// Web-intent share URLs (decision S8). The text is encoded by [Uri], so the
/// assertions decode the parameters back to the original strings.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/services/support/support_share_links.dart';

const _text = 'Mit WhisPaste sprechen & schreiben? Lokal, #frei + offen';

void main() {
  test('X uses the tweet intent with text and link as separate parameters', () {
    final uri = buildSupportShareUri(SupportShareTarget.x, text: _text);

    expect(uri.host, 'twitter.com');
    expect(uri.path, '/intent/tweet');
    expect(uri.queryParameters['text'], _text);
    expect(uri.queryParameters['url'], kWebsiteUrl);
  });

  test('Facebook shares the link only, as the sharer parameter u', () {
    final uri = buildSupportShareUri(SupportShareTarget.facebook, text: _text);

    expect(uri.host, 'www.facebook.com');
    expect(uri.path, '/sharer/sharer.php');
    expect(uri.queryParameters, {'u': kWebsiteUrl});
  });

  test('WhatsApp and Bluesky carry the text followed by the link', () {
    final whatsapp = buildSupportShareUri(
      SupportShareTarget.whatsapp,
      text: _text,
    );
    final bluesky = buildSupportShareUri(
      SupportShareTarget.bluesky,
      text: _text,
    );

    expect(whatsapp.host, 'wa.me');
    expect(whatsapp.queryParameters['text'], '$_text $kWebsiteUrl');
    expect(bluesky.host, 'bsky.app');
    expect(bluesky.path, '/intent/compose');
    expect(bluesky.queryParameters['text'], '$_text $kWebsiteUrl');
  });

  test('LinkedIn shares the link via share-offsite', () {
    final uri = buildSupportShareUri(SupportShareTarget.linkedin, text: _text);

    expect(uri.host, 'www.linkedin.com');
    expect(uri.path, '/sharing/share-offsite/');
    expect(uri.queryParameters['url'], kWebsiteUrl);
  });

  test('Reddit puts the text into the title and the link into url', () {
    final uri = buildSupportShareUri(SupportShareTarget.reddit, text: _text);

    expect(uri.host, 'www.reddit.com');
    expect(uri.path, '/submit');
    expect(uri.queryParameters['title'], _text);
    expect(uri.queryParameters['url'], kWebsiteUrl);
  });

  test('Telegram carries url and text as separate parameters', () {
    final uri = buildSupportShareUri(SupportShareTarget.telegram, text: _text);

    expect(uri.host, 't.me');
    expect(uri.path, '/share/url');
    expect(uri.queryParameters['url'], kWebsiteUrl);
    expect(uri.queryParameters['text'], _text);
  });

  test('email is a mailto URI whose subject and body decode exactly', () {
    final uri = buildSupportShareUri(
      SupportShareTarget.email,
      text: _text,
      subject: 'WhisPaste & Freunde',
    );
    final raw = uri.toString();

    expect(uri.scheme, 'mailto');
    expect(raw, startsWith('mailto:?subject='));
    expect(raw, contains('%20'), reason: 'mailto must not use form-encoded +');
    final query = raw.substring('mailto:?'.length);
    final params = {
      for (final pair in query.split('&'))
        pair.split('=').first: Uri.decodeComponent(pair.split('=').last),
    };
    expect(params['subject'], 'WhisPaste & Freunde');
    expect(params['body'], '$_text $kWebsiteUrl');
  });

  test('every target links to the canonical website domain', () {
    for (final target in SupportShareTarget.values) {
      final uri = buildSupportShareUri(target, text: 'x');
      final encoded = uri.toString();
      expect(
        encoded.contains(Uri.encodeComponent(kWebsiteUrl)) ||
            encoded.contains(kWebsiteUrl),
        isTrue,
        reason: '$target does not carry $kWebsiteUrl',
      );
    }
  });
}
