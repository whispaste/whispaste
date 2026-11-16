/// F34-2: clearAttention never throws. It runs unawaited after a successful
/// paste, so a failing cancel (no channel handler, an error that is no
/// PlatformException) must not end up as an unhandled error, and the cancel is
/// not retried on the next clear.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/system_attention_service.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifierChannel = MethodChannel('local_notifier');
  // macOS cancels via the lifecycle channel, Windows/Linux via the attention
  // channel; both answer the request and fail the cancel, so the test holds
  // on every host.
  const lifecycleChannel = MethodChannel('com.whispaste.app_lifecycle');
  const attentionChannel = MethodChannel('com.whispaste.attention');
  var cancelCalls = 0;

  Future<Object?> handler(MethodCall call) async {
    if (call.method == 'requestUserAttention') {
      return call.arguments is Map ? 1 : true;
    }
    if (call.method == 'cancelUserAttentionRequest') {
      cancelCalls++;
      throw StateError('runner gone');
    }
    return null;
  }

  setUp(() {
    cancelCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifierChannel, (_) async => true);
    messenger.setMockMethodCallHandler(lifecycleChannel, handler);
    messenger.setMockMethodCallHandler(attentionChannel, (call) async {
      // The Windows/Linux runner answers a bool for the request.
      if (call.method == 'requestUserAttention') return true;
      return handler(call);
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifierChannel, null);
    messenger.setMockMethodCallHandler(lifecycleChannel, null);
    messenger.setMockMethodCallHandler(attentionChannel, null);
  });

  test('a failing cancel is swallowed and not retried', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        systemAttentionServiceProvider.overrideWith(
          (ref) => SystemAttentionService(
            ref,
            isNotificationServerRunning: () async => false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final service = container.read(systemAttentionServiceProvider);

    await service.requestAttention(
      kind: AttentionKind.pasteFailedUnknown,
      title: 'title',
      body: 'body',
    );

    await expectLater(service.clearAttention(), completes);
    expect(cancelCalls, 1);

    // The failed cancel still ends the request; a second clear has nothing
    // left to cancel.
    await expectLater(service.clearAttention(), completes);
    expect(cancelCalls, 1);
  });
}
