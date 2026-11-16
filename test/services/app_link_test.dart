/// The whispaste:// links the app acts on. A link is untrusted input from any
/// web page: only the one bare path does something, the rest at most focuses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_link.dart';

void main() {
  test('the confirmation link is the newsletter link', () {
    expect(
      AppLink.parse(kNewsletterConfirmedLink),
      AppLink.newsletterConfirmed,
    );
    expect(
      AppLink.parse('WhisPaste://Newsletter/confirmed/'),
      AppLink.newsletterConfirmed,
    );
  });

  test('anything carrying data or another path is only an app link', () {
    for (final link in const [
      'whispaste://newsletter/confirmed?token=abc',
      'whispaste://newsletter/confirmed#x',
      'whispaste://user@newsletter/confirmed',
      'whispaste://newsletter:80/confirmed',
      'whispaste://newsletter/Confirmed',
      'whispaste://newsletter/confirmed/more',
      'whispaste://newsletter',
      'whispaste:newsletter/confirmed',
    ]) {
      expect(AppLink.parse(link), AppLink.other, reason: link);
    }
  });

  test('flags, files and other schemes are no link', () {
    for (final arg in const [
      '--toggle',
      '/home/anna/memo.ogg',
      r'C:\Users\anna\memo.ogg',
      'https://whispaste.de/newsletter/confirmed',
      '',
    ]) {
      expect(AppLink.parse(arg), AppLink.none, reason: arg);
    }
  });
}
