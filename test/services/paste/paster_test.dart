import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paster.dart';

class _FakeController implements DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;
  int typeCalls = 0;
  Duration? lastDelay;
  Duration? lastTypeDelay;
  String? lastTypedText;
  NativePasteResult pasteResult = const NativePasteResult(
    status: NativePasteStatus.success,
  );

  /// Defaults to non-success (NOT [NativePasteStatus.success], unlike
  /// [pasteResult]): `paste()` only retries via typing when the classic
  /// paste attempt itself fails (see `DesktopPaster.paste`) — leaving this
  /// non-success by default means a test would have to opt in to the
  /// fallback explicitly (by also setting a failing [pasteResult]) rather
  /// than accidentally exercise it.
  NativePasteResult typeResult = const NativePasteResult(
    status: NativePasteStatus.unknown,
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
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async {
    typeCalls++;
    lastTypeDelay = delay;
    lastTypedText = text;
    return typeResult;
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async => capabilityResult;

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

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

    test('returns failed for the generic postFailed bucket '
        '(post_failed / send_input_failed — NOT the UIPI foreground_blocked '
        'case, which has its own outcome, see below)', () async {
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
      'returns elevationBlocked when native reports foreground_blocked '
      '(Windows UIPI: target window runs elevated, WhisPaste does not)',
      () async {
        final controller = _FakeController()
          ..pasteResult = const NativePasteResult(
            status: NativePasteStatus.foregroundBlocked,
            detail: 'SetForegroundWindow refused — UIPI or stale window handle',
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.elevationBlocked);
      },
    );

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

  group('DesktopPaster.typeText', () {
    test(
      'returns success and calls typeText once, not pasteClipboard',
      () async {
        final controller = _FakeController()
          ..typeResult = const NativePasteResult(
            status: NativePasteStatus.success,
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.typeText(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.success);
        expect(controller.typeCalls, 1);
        expect(controller.pasteCalls, 0);
      },
    );

    test('forwards the text and delay unchanged', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      await paster.typeText(
        'hello world',
        const PasteOptions(autoPasteDelayMs: 300, blocklist: ''),
      );

      expect(controller.lastTypedText, 'hello world');
      expect(controller.lastTypeDelay, const Duration(milliseconds: 300));
    });

    test('does not touch the clipboard', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);
      clipboardContent = 'untouched';

      await paster.typeText(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(clipboardContent, 'untouched');
    });

    test('returns blocked when bundle ID matches blocklist', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'com.example.app';
      final paster = DesktopPaster(controller);

      final outcome = await paster.typeText(
        'hello',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: 'com.example.app, other.app',
        ),
      );

      expect(outcome, PasteOutcome.blocked);
      expect(controller.typeCalls, 0);
    });

    test('returns noTarget when native reports no captured target', () async {
      final controller = _FakeController()
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.noTarget,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.typeText(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.noTarget);
    });

    test(
      'returns permissionMissing when native reports permission missing',
      () async {
        final controller = _FakeController()
          ..typeResult = const NativePasteResult(
            status: NativePasteStatus.permissionMissing,
            detail: 'trusted=false',
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.typeText(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.permissionMissing);
      },
    );

    test('returns failed for the generic postFailed bucket', () async {
      final controller = _FakeController()
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.postFailed,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.typeText(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.failed);
    });
  });

  group('DesktopPaster.paste: the classic clipboard+paste-shortcut sequence '
      'is the default on every platform; direct Unicode typing is only a '
      'same-call fallback when the native paste shortcut fails to land '
      '(macOS/Windows) — assertions below branch on the actual host '
      'platform this suite runs on only for the fallback-specific cases; '
      'Linux has no native typeText handler, so a failed paste there is '
      'reported as-is', () {
    test('native paste succeeds: typing is never attempted, on any '
        'platform', () async {
      final controller = _FakeController()
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.success,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.success);
      expect(controller.pasteCalls, 1);
      expect(controller.typeCalls, 0);
    });

    test('native paste fails: falls back to direct typing on macOS/Windows; '
        'stays failed on Linux, which has no native typeText handler to '
        'fall back to', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.postFailed,
        )
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.success,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(controller.pasteCalls, 1);
      if (Platform.isMacOS || Platform.isWindows) {
        expect(outcome, PasteOutcome.success);
        expect(controller.typeCalls, 1);
      } else {
        expect(outcome, PasteOutcome.failed);
        expect(controller.typeCalls, 0);
      }
    });

    test('native paste fails and the typing fallback also fails: reports '
        'the original paste failure, not the typing failure', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.noTarget,
        )
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.postFailed,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.noTarget);
    });

    test('a failed native paste with multi-line text never falls back to '
        'typing, even though typing would succeed — CGEvent Unicode-typing '
        'delivers "\\n" as a literal Return keydown, which chat UIs '
        '(ChatGPT, Slack, ...) interpret as "submit"; reporting the paste '
        'failure is safer than risking an unwanted send', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.postFailed,
        )
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.success,
        );
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'line one\nline two',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.failed);
      expect(controller.typeCalls, 0);
      expect(controller.pasteCalls, 1);
    });

    test('the blocklist check runs once, before either mechanism is '
        'attempted', () async {
      final controller = _FakeController()..bundleIdToReturn = 'blocked.app';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: 'blocked.app'),
      );

      expect(outcome, PasteOutcome.blocked);
      expect(controller.typeCalls, 0);
      expect(controller.pasteCalls, 0);
    });
  });
}
