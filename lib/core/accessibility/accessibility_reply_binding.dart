/// Keeps `flutter/accessibility` messages from piling up as unanswered
/// platform messages on macOS (#200, #325).
///
/// The macOS engine never replies on `flutter/accessibility`: its handler in
/// FlutterEngine.mm (`setUpAccessibilityChannel`) drops the reply block,
/// while Windows and Linux always send an empty reply. Every message sent
/// with a reply callback therefore stays pending for the rest of the app's
/// life, held by the engine as a persistent handle. [announce] already sends
/// the app's own announcements without a callback, but the framework sends on
/// the same channel by itself: `SemanticsService.tooltip` each time a tooltip
/// opens (`RawTooltip`), semantics events (`RenderObject.sendSemanticsEvent`),
/// `ExpansionTile`, `Form` and `Autocomplete` announcements. The binding
/// below routes every message on that channel through [AccessibilityReplyMessenger],
/// which on macOS sends it without a reply callback and completes at once.
///
/// In debug builds the main engine keeps the flutter_driver binding (see
/// `main.dart`), so there only [announce] covers that engine. The secondary
/// render engines use [WpRenderEngineBinding] in every build.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'announce.dart' show announce;
import 'atspi_ids.dart';

/// Sends a platform message without a reply callback.
typedef FireAndForgetSend = void Function(String channel, ByteData? message);

/// Wraps the engine messenger. On a host whose engine never answers
/// `flutter/accessibility` ([engineAnswersAccessibility] false) messages on
/// that channel go out through [_sendWithoutReply] and the returned future
/// completes with null right away; everything else passes through unchanged.
class AccessibilityReplyMessenger implements BinaryMessenger {
  AccessibilityReplyMessenger(
    this._inner, {
    required this.engineAnswersAccessibility,
    FireAndForgetSend? sendWithoutReply,
  }) : _sendWithoutReply = sendWithoutReply ?? _platformSendWithoutReply;

  final BinaryMessenger _inner;

  /// False on macOS, see the library comment.
  final bool engineAnswersAccessibility;
  final FireAndForgetSend _sendWithoutReply;

  static void _platformSendWithoutReply(String channel, ByteData? message) => ui
      .PlatformDispatcher
      .instance
      .sendPlatformMessage(channel, message, null);

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (!engineAnswersAccessibility &&
        channel == SystemChannels.accessibility.name) {
      _sendWithoutReply(channel, message);
      return Future<ByteData?>.value();
    }
    return _inner.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _inner.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // BinaryMessenger still declares this member, so a wrapper has to
      // forward it; nothing in the app calls it.
      // ignore: deprecated_member_use
      _inner.handlePlatformMessage(channel, data, callback);
}

/// The messenger for the engine of [platform]: only the macOS engine leaves
/// `flutter/accessibility` unanswered.
AccessibilityReplyMessenger accessibilityReplyMessengerFor(
  BinaryMessenger inner,
  TargetPlatform platform, {
  FireAndForgetSend? sendWithoutReply,
}) => AccessibilityReplyMessenger(
  inner,
  engineAnswersAccessibility: platform != TargetPlatform.macOS,
  sendWithoutReply: sendWithoutReply,
);

/// Installs [AccessibilityReplyMessenger] as the binding's messenger.
mixin AccessibilityReplyMessengerBinding on BindingBase, ServicesBinding {
  @override
  BinaryMessenger createBinaryMessenger() => accessibilityReplyMessengerFor(
    super.createBinaryMessenger(),
    defaultTargetPlatform,
  );
}

/// Binding of the main engine: Sentry's binding (frame timing) plus the
/// accessibility messenger. Created in `main()` before
/// `SentryFlutter.init`, which then reuses it instead of creating its own.
class WpWidgetsBinding extends SentryWidgetsFlutterBinding
    with AccessibilityReplyMessengerBinding, AtspiIdsBinding {
  /// Returns the existing binding, or creates a [WpWidgetsBinding].
  static WidgetsBinding ensureInitialized() {
    if (!_bindingExists()) WpWidgetsBinding();
    return WidgetsBinding.instance;
  }
}

/// Binding of the secondary render engines (overlay, button, side panel,
/// snippet picker), which run without Sentry.
class WpRenderEngineBinding extends WidgetsFlutterBinding
    with AccessibilityReplyMessengerBinding, AtspiIdsBinding {
  /// Returns the existing binding, or creates a [WpRenderEngineBinding].
  static WidgetsBinding ensureInitialized() {
    if (!_bindingExists()) WpRenderEngineBinding();
    return WidgetsBinding.instance;
  }
}

/// Whether a binding already claimed the singleton (in debug builds the
/// flutter_driver binding does, see `main.dart`).
bool _bindingExists() {
  try {
    WidgetsBinding.instance;
    return true;
  } on Object {
    return false;
  }
}
