import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/method_channel_platform_host.dart';

// ── Minimal event type for testing ─────────────────────────────────────────

sealed class _TestEvent {
  const _TestEvent();
}

class _PingEvent extends _TestEvent {
  const _PingEvent(this.value);
  final String value;
}

class _OtherEvent extends _TestEvent {
  const _OtherEvent();
}

// ── Concrete host subclass for testing ─────────────────────────────────────

class _TestHost extends MethodChannelPlatformHost<_TestEvent> {
  _TestHost(super.channelName);

  @override
  _TestEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onPing':
        final value = (call.arguments as Map?)?['value'] as String? ?? '';
        return _PingEvent(value);
      case 'onOther':
        return const _OtherEvent();
      default:
        return null;
    }
  }

  /// Expose invokeMethod for white-box testing.
  Future<void> invokeNative(String method, [dynamic args]) =>
      invokeMethod(method, args);
}

// ── Helper: set a mock handler for [channelName] ────────────────────────────

void _setMock(
  String channelName,
  Future<dynamic> Function(MethodCall)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(channelName), handler);
}

/// Simulate a native → Dart call by encoding the call and dispatching it
/// through the binary messenger.
Future<void> _simulateNativeCall(
  String channelName,
  String method, [
  dynamic args,
]) async {
  const codec = StandardMethodCodec();
  final encoded = codec.encodeMethodCall(MethodCall(method, args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channelName, encoded, (_) {});
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.whispaste.test_host';

  // Suppress MissingPluginException for 'destroy' calls in dispose().
  setUp(() => _setMock(channelName, (call) async => null));
  tearDown(() => _setMock(channelName, null));

  // ── Disposed guard ──────────────────────────────────────────────────────

  group('disposed guard', () {
    test('isDisposed is false before dispose()', () async {
      final host = _TestHost(channelName);
      expect(host.isDisposed, isFalse);
      await host.dispose();
    });

    test('isDisposed is true after dispose()', () async {
      final host = _TestHost(channelName);
      await host.dispose();
      expect(host.isDisposed, isTrue);
    });

    test('dispose() is idempotent — second call is a no-op', () async {
      final host = _TestHost(channelName);
      await host.dispose();
      await expectLater(host.dispose(), completes);
    });

    test('invokeMethod is a no-op after dispose()', () async {
      final host = _TestHost(channelName);
      await host.dispose();

      final calls = <String>[];
      _setMock(channelName, (call) async {
        calls.add(call.method);
        return null;
      });

      await host.invokeNative('show');
      expect(calls, isEmpty);
    });
  });

  // ── Event broadcast ─────────────────────────────────────────────────────

  group('event broadcast', () {
    late _TestHost host;

    setUp(() => host = _TestHost(channelName));
    tearDown(() => host.dispose());

    test('events stream is a broadcast stream', () {
      expect(host.events.isBroadcast, isTrue);
    });

    test('known native event is forwarded to events stream', () async {
      final received = <_TestEvent>[];
      host.events.listen(received.add);

      await _simulateNativeCall(channelName, 'onPing', {'value': 'hello'});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first, isA<_PingEvent>());
      expect((received.first as _PingEvent).value, 'hello');
    });

    test('second known native event is forwarded', () async {
      final received = <_TestEvent>[];
      host.events.listen(received.add);

      await _simulateNativeCall(channelName, 'onOther');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first, isA<_OtherEvent>());
    });

    test('unknown native event is silently ignored', () async {
      final received = <_TestEvent>[];
      host.events.listen(received.add);

      await _simulateNativeCall(channelName, 'onUnknown');
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('multiple listeners all receive the same event (broadcast)', () async {
      final r1 = <_TestEvent>[];
      final r2 = <_TestEvent>[];
      host.events.listen(r1.add);
      host.events.listen(r2.add);

      await _simulateNativeCall(channelName, 'onPing', {'value': 'x'});
      await Future<void>.delayed(Duration.zero);

      expect(r1, hasLength(1));
      expect(r2, hasLength(1));
    });

    test('events stream is closed after dispose()', () async {
      bool done = false;
      host.events.listen((_) {}, onDone: () => done = true);
      await host.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    test(
      'native events received after dispose() are silently dropped',
      () async {
        final received = <_TestEvent>[];
        // Listen before dispose.
        host.events.listen(received.add);
        await host.dispose();

        // Re-install mock so the platform message routing works.
        _setMock(channelName, (call) async => null);

        // The host's handler was cleared in dispose() so this call goes nowhere,
        // but it must not throw.
        await _simulateNativeCall(channelName, 'onPing', {'value': 'late'});
        await Future<void>.delayed(Duration.zero);

        expect(received, isEmpty);
      },
    );
  });

  // ── Method-call routing ─────────────────────────────────────────────────

  group('method-call routing', () {
    late _TestHost host;
    final calls = <String>[];

    setUp(() {
      calls.clear();
      host = _TestHost(channelName);
      _setMock(channelName, (call) async {
        calls.add(call.method);
        return null;
      });
    });

    tearDown(() => host.dispose());

    test('invokeMethod forwards call to the MethodChannel', () async {
      await host.invokeNative('show', {'x': 100.0, 'y': 200.0});
      expect(calls, contains('show'));
    });

    test('multiple methods are forwarded independently', () async {
      await host.invokeNative('show');
      await host.invokeNative('hide');
      await host.invokeNative('setTheme', {'isDark': true});
      expect(calls, containsAll(['show', 'hide', 'setTheme']));
    });

    test('invokeMethod is skipped when disposed', () async {
      await host.dispose();
      calls.clear();
      _setMock(channelName, (call) async {
        calls.add(call.method);
        return null;
      });

      await host.invokeNative('show');
      expect(calls, isNot(contains('show')));
    });
  });
}
