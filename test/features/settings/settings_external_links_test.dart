/// Guard: the settings page opens no external link with `launchUrl` directly;
/// links go through the shared `openExternalUrl` helper, so a missing browser
/// shows the same error toast everywhere (UIA-SET-09 / UIA-HLP-01 follow-up).
/// Its search empty state opens the in-app help instead (UIA-SET-11).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings_page.dart opens links via openExternalUrl, not launchUrl', () {
    final source = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('launchUrl(')));
    expect(source, isNot(contains('kGitHubRepoUrl')));
  });
}
