import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
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

  /// Defaults to `false` (unsupported), matching macOS/Linux and Windows
  /// builds without the native exclusion — existing tests exercise the
  /// `Clipboard.setData` fallback via the mocked platform channel below.
  /// Tests for issue #146's native path opt in explicitly.
  bool writeExcludingHistoryResult = false;
  final List<String> writeExcludingHistoryCalls = <String>[];

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
  Future<NativePasteResult> copySelection({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.unknown);

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
  Future<bool> writeClipboardTextExcludingHistory(String text) async {
    writeExcludingHistoryCalls.add(text);
    return writeExcludingHistoryResult;
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

/// Scriptable [ClipboardReceiptBridge] — stands in for the macOS/Windows
/// native receipt write (lazy pasteboard provider / delayed rendering).
class _FakeReceiptBridge implements ClipboardReceiptBridge {
  bool writeResult = true;
  Object? writeError;
  final List<String> receiptWrites = <String>[];
  final List<String> restores = <String>[];
  ClipboardRestoreOutcome restoreOutcome = ClipboardRestoreOutcome.restored;

  /// Completes the pending [waitForClipboardRead] — left uncompleted, the
  /// paster has to fall back to its fixed timeout.
  final Completer<ClipboardReadReceipt> read =
      Completer<ClipboardReadReceipt>();

  @override
  Future<bool> writeClipboardTextWithReceipt(String text) async {
    receiptWrites.add(text);
    if (writeError != null) throw writeError!;
    return writeResult;
  }

  @override
  Future<ClipboardReadReceipt> waitForClipboardRead() => read.future;

  @override
  Future<ClipboardRestoreOutcome> restoreClipboardTextIfOwner(
    String text,
  ) async {
    restores.add(text);
    return restoreOutcome;
  }
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

  group('DesktopPaster.paste — clipboard-history exclusion (issue #146)', () {
    test('falls back to Clipboard.setData for both the write and the restore '
        'when the native exclusion is unsupported (returns false)', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.success);
      // Both the transient write and the restore went through the
      // (unsupported-on-this-platform) native path first...
      expect(controller.writeExcludingHistoryCalls, [
        'hello',
        'previous clipboard value',
      ]);
      // ...then fell back to the plain channel, ending with the restored
      // value back on the clipboard.
      expect(clipboardContent, 'previous clipboard value');
    });

    test(
      'never touches Clipboard.setData when the native exclusion succeeds, '
      'and still restores the previous value through the native call',
      () async {
        clipboardContent = 'previous clipboard value';
        final controller = _FakeController()
          ..writeExcludingHistoryResult = true;
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.success);
        expect(controller.writeExcludingHistoryCalls, [
          'hello',
          'previous clipboard value',
        ]);
        // The mocked Clipboard.setData handler was never hit, so the value
        // it captured is still the pre-paste snapshot, not the transcript.
        expect(clipboardContent, 'previous clipboard value');
      },
    );

    test(
      'restores an empty string when there was no prior clipboard text',
      () async {
        clipboardContent = null;
        final controller = _FakeController();
        final paster = DesktopPaster(controller);

        await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(controller.writeExcludingHistoryCalls, ['hello', '']);
      },
    );
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
      'Linux skips the retry too — its typeText routes through the same '
      'clipboard+uinput-Ctrl+V path as pasteClipboard, so retrying it after '
      'a failed paste would just reproduce the same failure — a failed '
      'paste there is reported as-is', () {
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

    test(
      'native paste fails: falls back to direct typing on macOS/Windows; '
      'stays failed on Linux, which skips the retry (see group doc)',
      () async {
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
      },
    );

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

  group('DesktopPaster.paste — receipt-based clipboard restore', () {
    const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

    test('writes the transcript through the receipt bridge instead of the '
        'plain transient write, and restores through the ownership-checked '
        'bridge call', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final paster = DesktopPaster(controller, receipts: bridge);

      final outcome = await paster.paste('hello', options);

      expect(outcome, PasteOutcome.success);
      expect(bridge.receiptWrites, ['hello']);
      expect(bridge.restores, ['previous clipboard value']);
      // Neither the plain transient write nor Clipboard.setData ran.
      expect(controller.writeExcludingHistoryCalls, isEmpty);
      expect(clipboardContent, 'previous clipboard value');
    });

    test('restores a short safety margin after the read receipt instead of '
        'waiting the fixed buffer', () {
      fakeAsync((async) {
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        var done = false;
        paster.paste('hello', options).then((_) => done = true);
        async.flushMicrotasks();

        bridge.read.complete(ClipboardReadReceipt.read);
        async.elapse(
          DesktopPaster.receiptSafetyMargin - const Duration(milliseconds: 1),
        );
        expect(bridge.restores, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(bridge.restores, hasLength(1));
        expect(done, isTrue);
        // Well under the old fixed ≥500 ms buffer.
        expect(async.elapsed, lessThan(const Duration(milliseconds: 500)));
      });
    });

    test('falls back to the fixed buffer when no read receipt arrives, and '
        'still restores only through the ownership check', () {
      fakeAsync((async) {
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        paster.paste('hello', options);
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 499));
        expect(bridge.restores, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(bridge.restores, hasLength(1));
      });
    });

    test('the timeout fallback keeps the old delay-dependent buffer', () {
      fakeAsync((async) {
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 300, blocklist: ''),
        );
        async.flushMicrotasks();

        // max(500, 300 + 350) = 650 ms.
        async.elapse(const Duration(milliseconds: 649));
        expect(bridge.restores, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(bridge.restores, hasLength(1));
      });
    });

    test('never restores when another process took over the clipboard while '
        'waiting', () async {
      clipboardContent = 'previous clipboard value';
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.ownershipLost);
      final paster = DesktopPaster(_FakeController(), receipts: bridge);

      final outcome = await paster.paste('hello', options);

      expect(outcome, PasteOutcome.success);
      expect(bridge.restores, isEmpty);
    });

    test('a not-owner restore result is not a paste failure', () async {
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read)
        ..restoreOutcome = ClipboardRestoreOutcome.notOwner;
      final paster = DesktopPaster(_FakeController(), receipts: bridge);

      expect(await paster.paste('hello', options), PasteOutcome.success);
    });

    test('falls back to the classic write + fixed-delay restore when the '
        'receipt write is unavailable', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final bridge = _FakeReceiptBridge()..writeResult = false;
      final paster = DesktopPaster(controller, receipts: bridge);

      final outcome = await paster.paste('hello', options);

      expect(outcome, PasteOutcome.success);
      expect(controller.writeExcludingHistoryCalls, [
        'hello',
        'previous clipboard value',
      ]);
      expect(bridge.restores, isEmpty);
      expect(clipboardContent, 'previous clipboard value');
    });

    test(
      'falls back to the classic path when the receipt write throws',
      () async {
        final controller = _FakeController();
        final bridge = _FakeReceiptBridge()
          ..writeError = MissingPluginException('no handler');
        final paster = DesktopPaster(controller, receipts: bridge);

        expect(await paster.paste('hello', options), PasteOutcome.success);
        expect(controller.writeExcludingHistoryCalls, hasLength(2));
        expect(bridge.restores, isEmpty);
      },
    );

    test('a failed paste leaves the transcript on the clipboard (no restore), '
        'same as before', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.noTarget,
        );
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final paster = DesktopPaster(controller, receipts: bridge);

      expect(await paster.paste('hello', options), PasteOutcome.noTarget);
      expect(bridge.restores, isEmpty);
    });
  });
}
