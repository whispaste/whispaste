/// #1852: notices switched off with "Don't show again" are kept per notice
/// in `muted_notices`; nothing changes for an installation without the key.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/mutable_notice.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  const notice = MutableNotice.pasteUnconfirmed;

  test('an existing installation without the key mutes nothing', () {
    final s = InterfaceSettings.fromMap(const {'show_notifications': 'true'});
    expect(s.mutedNotices, isEmpty);
    expect(s.isNoticeMuted(notice), isFalse);
    expect(InterfaceSettings.defaults.mutedNotices, isEmpty);
  });

  test('a muted notice survives saving and loading', () {
    final muted = InterfaceSettings.defaults.withNoticeMuted(
      notice,
      muted: true,
    );
    final loaded = InterfaceSettings.fromMap(muted.toMap());
    expect(loaded.isNoticeMuted(notice), isTrue);
    expect(loaded, muted);
  });

  test('muting twice stores the id once; showing again removes it', () {
    final twice = InterfaceSettings.defaults
        .withNoticeMuted(notice, muted: true)
        .withNoticeMuted(notice, muted: true);
    expect(twice.mutedNotices, [notice.id]);
    expect(twice.withNoticeMuted(notice, muted: false).mutedNotices, isEmpty);
  });

  test('an id from a newer version is kept and written back', () {
    final s = InterfaceSettings.fromMap(const {
      'muted_notices': '["future-notice"]',
    });
    expect(s.isNoticeMuted(notice), isFalse);
    final both = s.withNoticeMuted(notice, muted: true);
    expect(InterfaceSettings.fromMap(both.toMap()).mutedNotices, [
      'future-notice',
      notice.id,
    ]);
    expect(MutableNotice.fromId('future-notice'), isNull);
  });

  test('a damaged value mutes nothing', () {
    final s = InterfaceSettings.fromMap(const {'muted_notices': '{oops'});
    expect(s.mutedNotices, isEmpty);
  });

  test('ids are stable', () {
    expect(MutableNotice.fromId('paste-unconfirmed'), notice);
  });
}
