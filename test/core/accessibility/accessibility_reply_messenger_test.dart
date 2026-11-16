// Channel contract of AccessibilityReplyMessenger (#325): on macOS the engine
// never answers flutter/accessibility, so a message there must not wait for a
// reply; every other channel and every other host keeps the engine path.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/accessibility/accessibility_reply_binding.dart';

/// Engine stand-in that, like the macOS engine on flutter/accessibility,
/// never replies.
class _SilentEngine implements BinaryMessenger {
  final sent = <String>[];

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent.add(channel);
    return Completer<ByteData?>().future;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {}
}

ByteData _tooltipMessage() => SystemChannels.accessibility.codec.encodeMessage(
  const TooltipSemanticsEvent('Copy').toMap(),
)!;

void main() {
  final accessibility = SystemChannels.accessibility.name;

  test('macOS: accessibility goes out without reply and completes', () {
    fakeAsync((async) {
      final engine = _SilentEngine();
      final fireAndForget = <String>[];
      final messenger = AccessibilityReplyMessenger(
        engine,
        engineAnswersAccessibility: false,
        sendWithoutReply: (channel, _) => fireAndForget.add(channel),
      );

      var done = false;
      unawaited(
        messenger
            .send(accessibility, _tooltipMessage())!
            .then((_) => done = true),
      );
      async.flushMicrotasks();

      expect(done, isTrue, reason: 'no reply is awaited from the engine');
      expect(fireAndForget, [accessibility]);
      expect(engine.sent, isEmpty);
    });
  });

  test('macOS: other channels still go through the engine', () {
    final engine = _SilentEngine();
    final fireAndForget = <String>[];
    final messenger = AccessibilityReplyMessenger(
      engine,
      engineAnswersAccessibility: false,
      sendWithoutReply: (channel, _) => fireAndForget.add(channel),
    );

    messenger.send('whispaste/paste', null);

    expect(engine.sent, ['whispaste/paste']);
    expect(fireAndForget, isEmpty);
  });

  test('Windows/Linux: accessibility keeps the engine reply', () {
    final engine = _SilentEngine();
    final fireAndForget = <String>[];
    final messenger = AccessibilityReplyMessenger(
      engine,
      engineAnswersAccessibility: true,
      sendWithoutReply: (channel, _) => fireAndForget.add(channel),
    );

    messenger.send(accessibility, _tooltipMessage());

    expect(engine.sent, [accessibility]);
    expect(fireAndForget, isEmpty);
  });

  group('platform choice', _platformChoice);
  group('entry points', _bindingGuard);
}

void _platformChoice() {
  for (final (platform, answers) in [
    (TargetPlatform.macOS, false),
    (TargetPlatform.windows, true),
    (TargetPlatform.linux, true),
  ]) {
    test('${platform.name}: engine reply on accessibility is $answers', () {
      final engine = _SilentEngine();
      final fireAndForget = <String>[];
      accessibilityReplyMessengerFor(
        engine,
        platform,
        sendWithoutReply: (channel, _) => fireAndForget.add(channel),
      ).send(SystemChannels.accessibility.name, _tooltipMessage());

      expect(engine.sent.isNotEmpty, answers);
      expect(fireAndForget.isEmpty, answers);
    });
  }
}

/// The fix only works where an engine starts on the wrapped binding: the
/// main engine and the secondary render engines must not create a plain
/// WidgetsFlutterBinding first.
void _bindingGuard() {
  test('engine entry points use the accessibility binding', () {
    final entryPoints = [
      File('lib/main.dart'),
      for (final f in Directory('lib').listSync())
        if (f is File && f.path.endsWith('_render_entrypoint.dart')) f,
    ];
    final offenders = [
      for (final f in entryPoints)
        if (f.readAsStringSync().contains(
          'WidgetsFlutterBinding.ensureInitialized()',
        ))
          f.path,
    ];
    expect(entryPoints.length, greaterThan(1));
    expect(offenders, isEmpty);
  });
}
