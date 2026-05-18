import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paster.dart';

class _FakeController implements DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;
  Duration? lastDelay;
  NativePasteResult pasteResult = const NativePasteResult(
    status: NativePasteStatus.success,
  );
  NativeCapabilityResult capabilityResult = const NativeCapabilityResult(
    status: NativeCapabilityStatus.ready,
  );
  String? bundleIdToReturn;

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls++;
    return true;
  }

  @override
  Future<String?> getTargetBundleId() async => bundleIdToReturn;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls++;
    lastDelay = delay;
    return pasteResult;
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async => capabilityResult;

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the clipboard platform channel
  String? clipboardContent;
  setUp(() {
    clipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardContent = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardContent == null) return null;
              return <String, dynamic>{'text': clipboardContent};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('DesktopPaster', () {
    test('returns success and calls paste once', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.success);
      expect(controller.pasteCalls, 1);
    });

    test('delay passthrough: autoPasteDelayMs=0 → Duration.zero', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      await paster.paste(
        'hi',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(controller.lastDelay, Duration.zero);
    });

    test('delay passthrough: autoPasteDelayMs=300 → 300ms', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      await paster.paste(
        'hi',
        const PasteOptions(autoPasteDelayMs: 300, blocklist: ''),
      );

      expect(controller.lastDelay, const Duration(milliseconds: 300));
    });

    test('returns blocked when bundle ID matches blocklist', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'com.example.app';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: 'com.example.app, other.app',
        ),
      );

      expect(outcome, PasteOutcome.blocked);
      expect(controller.pasteCalls, 0);
    });

    test('blocklist check is case-insensitive', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'COM.EXAMPLE.APP';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
      );

      expect(outcome, PasteOutcome.blocked);
    });

    test('empty blocklist does not block', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'com.example.app';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.success);
    });

    test('prime calls capturePasteTarget', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      await paster.prime();

      expect(controller.captureCalls, 1);
    });

    test('returns failed when pasteClipboard returns unknown error', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.postFailed,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.failed);
    });

    test(
      'returns permissionMissing when native reports no accessibility',
      () async {
        final controller = _FakeController()
          ..pasteResult = const NativePasteResult(
            status: NativePasteStatus.permissionMissing,
            detail: 'AXIsProcessTrusted=false',
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.permissionMissing);
      },
    );

    test('returns noTarget when native reports no captured target', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.noTarget,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.noTarget);
    });

    test('checkCapability forwards native readiness result', () async {
      final controller = _FakeController()
        ..capabilityResult = const NativeCapabilityResult(
          status: NativeCapabilityStatus.permissionMissing,
          canPrompt: true,
        );
      final paster = DesktopPaster(controller);

      final cap = await paster.checkCapability();

      expect(cap.status, PasteCapabilityStatus.permissionMissing);
      expect(cap.canPrompt, isTrue);
    });
  });
}
