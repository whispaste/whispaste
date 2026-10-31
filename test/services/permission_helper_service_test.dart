/// Channel contract of [PermissionHelperService]: what `show`/`hide` send to
/// `whispaste/permission_helper`, how the answers map, the native events,
/// and that Windows/Linux never call a native host.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/permission_helper_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whispaste/permission_helper');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? Function(MethodCall) answer;

  setUp(() {
    calls = [];
    answer = (_) => 'shown';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final a = answer(call);
      if (a is Exception) throw a;
      return a;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> nativeSends(String method, Map<String, String> args) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  test('show sends the kind and the localised texts', () async {
    final service = PermissionHelperService(isMacOS: true);
    addTearDown(service.dispose);
    expect(
      await service.show(
        PermissionHelperKind.accessibility,
        text: 'Drag',
        closeLabel: 'Close',
      ),
      PermissionHelperShowResult.shown,
    );
    expect(calls.single.method, 'show');
    expect(calls.single.arguments, {
      'kind': 'accessibility',
      'text': 'Drag',
      'closeLabel': 'Close',
    });
  });

  test('native answers map to results', () async {
    final service = PermissionHelperService(isMacOS: true);
    addTearDown(service.dispose);
    Future<PermissionHelperShowResult> show() => service.show(
      PermissionHelperKind.accessibility,
      text: 't',
      closeLabel: 'c',
    );

    answer = (_) => 'granted';
    expect(await show(), PermissionHelperShowResult.granted);
    answer = (_) => 'unsupported';
    expect(await show(), PermissionHelperShowResult.unsupported);
    answer = (_) => 'something else';
    expect(await show(), PermissionHelperShowResult.failed);
    answer = (_) => PlatformException(code: 'INVALID_ARGS');
    expect(await show(), PermissionHelperShowResult.failed);
  });

  test('a missing native host is failed, not thrown', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final service = PermissionHelperService(isMacOS: true);
    addTearDown(service.dispose);
    expect(
      await service.show(
        PermissionHelperKind.accessibility,
        text: 't',
        closeLabel: 'c',
      ),
      PermissionHelperShowResult.failed,
    );
    await service.hide();
  });

  test('Windows and Linux answer unsupported without a native call', () async {
    final service = PermissionHelperService(isMacOS: false);
    addTearDown(service.dispose);
    expect(
      await service.show(
        PermissionHelperKind.accessibility,
        text: 't',
        closeLabel: 'c',
      ),
      PermissionHelperShowResult.unsupported,
    );
    await service.hide();
    expect(calls, isEmpty);
  });

  test('hide sends hide', () async {
    final service = PermissionHelperService(isMacOS: true);
    addTearDown(service.dispose);
    answer = (_) => null;
    await service.hide();
    expect(calls.single.method, 'hide');
  });

  test('native granted and closed events reach the stream', () async {
    final service = PermissionHelperService(isMacOS: true);
    addTearDown(service.dispose);
    final events = <PermissionHelperEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);

    await nativeSends('granted', {'kind': 'accessibility'});
    await nativeSends('closed', {'kind': 'accessibility', 'reason': 'timeout'});
    await nativeSends('closed', {
      'kind': 'accessibility',
      'reason': 'cancelled',
    });
    // Unknown kinds, reasons and methods are ignored.
    await nativeSends('closed', {'kind': 'camera', 'reason': 'timeout'});
    await nativeSends('closed', {'kind': 'accessibility', 'reason': 'x'});
    await nativeSends('other', {'kind': 'accessibility'});
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      (
        kind: PermissionHelperKind.accessibility,
        reason: PermissionHelperCloseReason.granted,
      ),
      (
        kind: PermissionHelperKind.accessibility,
        reason: PermissionHelperCloseReason.timeout,
      ),
      (
        kind: PermissionHelperKind.accessibility,
        reason: PermissionHelperCloseReason.cancelled,
      ),
    ]);
  });
}
