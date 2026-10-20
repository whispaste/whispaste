/// WP-43a A-M7: the multiline preview must not outlive the API client. If the
/// client gives up first, the preview stays open and a later confirm pastes
/// into a request nobody is waiting for.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/automation_api_client.dart';
import 'package:whispaste/services/automation_api/multiline_paste_confirmation.dart';

void main() {
  test('the preview wait ends before the client gives up', () {
    expect(kAutomationPreviewWait, lessThanOrEqualTo(kAutomationClientTimeout));
  });

  test('the preview wait is shorter than the default confirmation timeout', () {
    expect(
      kAutomationPreviewWait,
      lessThanOrEqualTo(kMultilinePasteConfirmTimeout),
    );
  });
}
