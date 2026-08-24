/// Unit tests for [clipboardHistoryCapabilityFor].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_platform_capability.dart';

void main() {
  group('clipboardHistoryCapabilityFor', () {
    test('macOS gets rolling history', () {
      expect(
        clipboardHistoryCapabilityFor(TargetPlatform.macOS),
        ClipboardHistoryCapability.rollingHistory,
      );
    });

    test('Windows gets rolling history', () {
      expect(
        clipboardHistoryCapabilityFor(TargetPlatform.windows),
        ClipboardHistoryCapability.rollingHistory,
      );
    });

    test('Linux only gets a snapshot on open', () {
      expect(
        clipboardHistoryCapabilityFor(TargetPlatform.linux),
        ClipboardHistoryCapability.snapshotOnly,
      );
    });
  });
}
