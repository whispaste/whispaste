/// Unit tests for [AppClipboard].
///
/// Two critical properties under test:
/// - Ordering: on a platform with a rolling clipboard monitor,
///   [AppClipboard.setText] must signal [SelfWriteSignal.markSelfWrite]
///   *before* the actual `Clipboard.setData` platform call, never after --
///   see PRD.md "Self-Write-Suppression" for why the reversed order is a
///   real race, not an acceptable simplification.
/// - Capability gating: on a platform with no rolling monitor (e.g. Linux,
///   snapshot-only per PRD.md), the native signal must not fire at all --
///   there is no monitor to mark against, so it would just be a pointless
///   channel round trip on every paste.
///
/// The Dart-side [SelfWriteSuppressionRegistry] is always marked regardless
/// of platform, since the Linux snapshot-on-open path (issue 06) has no
/// native monitor and consults it directly.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/app_clipboard.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';
import 'package:whispaste/services/clipboard_history/self_write_signal.dart';
import 'package:whispaste/services/clipboard_history/self_write_suppression_registry.dart';

class _RecordingSignal implements SelfWriteSignal {
  final List<String> events;
  _RecordingSignal(this.events);

  @override
  Future<void> markSelfWrite(ClipboardFingerprint fingerprint) async {
    events.add('mark');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> events;
  late String? clipboardText;

  setUp(() {
    events = [];
    clipboardText = null;
    AppClipboard.signal = _RecordingSignal(events);
    AppClipboard.registry = SelfWriteSuppressionRegistry();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            events.add('write');
            final args = Map<String, dynamic>.from(call.arguments as Map);
            clipboardText = args['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    AppClipboard.signal = const MethodChannelSelfWriteSignal();
    AppClipboard.registry = SelfWriteSuppressionRegistry();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('AppClipboard.setText on a rolling-history platform (macOS)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test('marks the native signal before writing to the clipboard', () async {
      await AppClipboard.setText('hello');
      expect(events, ['mark', 'write']);
    });

    test('writes the exact given text', () async {
      await AppClipboard.setText('hello world');
      expect(clipboardText, 'hello world');
    });

    test('marks the Dart-side suppression registry', () async {
      await AppClipboard.setText('hello');
      expect(
        AppClipboard.registry.shouldSuppress(
          ClipboardFingerprint.ofText('hello'),
        ),
        isTrue,
      );
    });
  });

  group('AppClipboard.setText on a snapshot-only platform (Linux)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    });

    test('never fires the native signal', () async {
      await AppClipboard.setText('hello');
      expect(events, ['write']);
    });

    test('still marks the Dart-side suppression registry', () async {
      await AppClipboard.setText('hello');
      expect(
        AppClipboard.registry.shouldSuppress(
          ClipboardFingerprint.ofText('hello'),
        ),
        isTrue,
      );
    });
  });

  group('MethodChannelSelfWriteSignal', () {
    test('does not throw when no native handler is installed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.whispaste.clipboard_history'),
            null,
          );
      await expectLater(
        const MethodChannelSelfWriteSignal().markSelfWrite(
          ClipboardFingerprint.ofText('hello'),
        ),
        completes,
      );
    });
  });
}
