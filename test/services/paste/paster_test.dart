import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:whispaste/services/clipboard_history/app_clipboard.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';
import 'package:whispaste/services/clipboard_history/self_write_suppression_registry.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
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

  /// When set, [getTargetBundleId] throws it (AUF-1: lookup failure).
  Object? bundleLookupError;

  /// Defaults to `false` (unsupported), matching macOS/Linux and Windows
  /// builds without the native exclusion — existing tests exercise the
  /// `Clipboard.setData` fallback via the mocked platform channel below.
  /// Tests for issue #146's native path opt in explicitly.
  bool writeExcludingHistoryResult = false;

  /// Runs inside the paste shortcut, i.e. while the paste window is open.
  void Function()? onPasteShortcut;

  /// When set, the first native paste waits on it before answering.
  Completer<void>? firstPasteGate;

  /// Mirrors a successful native write into the test's clipboard model.
  void Function(String text)? onSystemClipboardWrite;
  final List<String> writeExcludingHistoryCalls = <String>[];

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls++;
    return true;
  }

  @override
  Future<String?> getTargetBundleId() async {
    final error = bundleLookupError;
    if (error != null) throw error;
    return bundleIdToReturn;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls++;
    if (pasteCalls == 1) await firstPasteGate?.future;
    lastDelay = delay;
    onPasteShortcut?.call();
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
    // A successful native write lands on the system clipboard, which the
    // Flutter read in the restore check sees as well.
    if (writeExcludingHistoryResult) onSystemClipboardWrite?.call(text);
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
    if (writeResult) onSystemClipboardWrite?.call(text);
    return writeResult;
  }

  /// Mirrors a successful receipt write into the test's clipboard model.
  void Function(String text)? onSystemClipboardWrite;

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

/// Scriptable [ClipboardSnapshotBridge]: stands in for the native full
/// clipboard backup (all formats held by the host).
class _FakeSnapshotBridge implements ClipboardSnapshotBridge {
  ClipboardSnapshot snapshot = const ClipboardSnapshot(
    ClipboardSnapshotStatus.saved,
    formats: 2,
    bytes: 4096,
  );
  ClipboardRestoreOutcome restoreOutcome = ClipboardRestoreOutcome.restored;
  int snapshots = 0;
  int restores = 0;
  int discards = 0;

  @override
  Future<ClipboardSnapshot> snapshotClipboard() async {
    snapshots++;
    return snapshot;
  }

  @override
  Future<ClipboardRestoreOutcome> restoreClipboardSnapshotIfOwner() async {
    restores++;
    return restoreOutcome;
  }

  @override
  Future<void> discardClipboardSnapshot() async {
    discards++;
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

  group('copy-to-clipboard switch off (maintainer 4a+c)', () {
    test(
      'a listed target writes nothing to any clipboard and pastes nothing',
      () async {
        final controller = _FakeController()
          ..bundleIdToReturn = 'com.example.app';
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'secret text',
          const PasteOptions(
            autoPasteDelayMs: 0,
            blocklist: 'com.example.app',
            copyBlockedToClipboard: false,
          ),
        );

        expect(outcome, PasteOutcome.blocked);
        expect(controller.pasteCalls, 0);
        expect(controller.writeExcludingHistoryCalls, isEmpty);
        expect(clipboardContent, isNull);
      },
    );

    test('an unknown target writes nothing to any clipboard', () async {
      final controller = _FakeController()..bundleIdToReturn = null;
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'secret text',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: 'com.example.app',
          copyBlockedToClipboard: false,
        ),
      );

      expect(outcome, PasteOutcome.blocked);
      expect(controller.pasteCalls, 0);
      expect(controller.writeExcludingHistoryCalls, isEmpty);
      expect(clipboardContent, isNull);
    });

    test(
      'typing into a listed target writes nothing and types nothing',
      () async {
        final controller = _FakeController()
          ..bundleIdToReturn = 'com.example.app';
        final paster = DesktopPaster(controller);

        final outcome = await paster.typeText(
          'secret text',
          const PasteOptions(
            autoPasteDelayMs: 0,
            blocklist: 'com.example.app',
            copyBlockedToClipboard: false,
          ),
        );

        expect(outcome, PasteOutcome.blocked);
        expect(controller.typeCalls, 0);
        expect(controller.writeExcludingHistoryCalls, isEmpty);
        expect(clipboardContent, isNull);
      },
    );

    test('typing into an unknown target writes nothing', () async {
      final controller = _FakeController()..bundleIdToReturn = null;
      final paster = DesktopPaster(controller);

      await paster.typeText(
        'secret text',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: 'com.example.app',
          copyBlockedToClipboard: false,
        ),
      );

      expect(controller.typeCalls, 0);
      expect(controller.writeExcludingHistoryCalls, isEmpty);
      expect(clipboardContent, isNull);
    });

    test('the switch on still copies a blocked paste (default)', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'com.example.app';
      final paster = DesktopPaster(controller);

      await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
      );

      expect(controller.pasteCalls, 0);
      expect(controller.writeExcludingHistoryCalls, ['hello']);
    });

    test('an empty blocklist with an unknown target pastes normally', () async {
      final controller = _FakeController()..bundleIdToReturn = null;
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: '',
          copyBlockedToClipboard: false,
        ),
      );

      expect(outcome, isNot(PasteOutcome.blocked));
      expect(controller.pasteCalls, 1);
    });
  });

  group('DesktopPaster', () {
    test(
      'a sent shortcut without a read receipt on a platform without a receipt bridge is unconfirmedNoBridge, and calls paste once',
      () async {
        final controller = _FakeController();
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.unconfirmedNoBridge);
        expect(controller.pasteCalls, 1);
      },
    );

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

    test(
      'GS-075: a blocked paste leaves the transcript on the clipboard',
      () async {
        final controller = _FakeController()
          ..bundleIdToReturn = 'com.example.app';
        final paster = DesktopPaster(controller);

        await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
        );

        expect(controller.pasteCalls, 0);
        expect(controller.writeExcludingHistoryCalls, ['hello']);
      },
    );

    test(
      'GS-075: a blocked typing leaves the transcript on the clipboard',
      () async {
        final controller = _FakeController()
          ..bundleIdToReturn = 'com.example.app';
        final paster = DesktopPaster(controller);

        await paster.typeText(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
        );

        expect(controller.typeCalls, 0);
        expect(controller.writeExcludingHistoryCalls, ['hello']);
      },
    );

    test(
      'GS-075: an unknown target also leaves the transcript on the clipboard',
      () async {
        final controller = _FakeController()..bundleIdToReturn = null;
        final paster = DesktopPaster(controller);

        await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
        );

        expect(controller.pasteCalls, 0);
        expect(controller.writeExcludingHistoryCalls, ['hello']);
      },
    );

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

    test(
      'AUF-1: an unknown target fails closed when the list is set',
      () async {
        final controller = _FakeController();
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: 'com.example.app'),
        );

        expect(outcome, PasteOutcome.blocked);
        expect(controller.pasteCalls, 0);
      },
    );

    test('AUF-1: a failing target lookup fails closed as well', () async {
      final controller = _FakeController()
        ..bundleLookupError = MissingPluginException();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: '1password'),
      );

      expect(outcome, PasteOutcome.blocked);
      expect(controller.pasteCalls, 0);
    });

    test('AUF-1: an unknown target does not block an empty list', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ' , '),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
    });

    test('empty blocklist does not block', () async {
      final controller = _FakeController()
        ..bundleIdToReturn = 'com.example.app';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
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
      'permissionMissing keeps the transcript on the clipboard for a manual paste',
      () async {
        clipboardContent = null;
        final controller = _FakeController()
          ..pasteResult = const NativePasteResult(
            status: NativePasteStatus.permissionMissing,
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.permissionMissing);
        expect(
          clipboardContent,
          'hello',
          reason: 'the failure message promises the text is on the clipboard',
        );
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

  group(
    'DesktopPaster.paste — restore only over an unchanged clipboard (ticket, 9.9)',
    () {
      test(
        'a copy the user makes during the paste window is not overwritten',
        () async {
          clipboardContent = 'previous clipboard value';
          final controller = _FakeController()
            ..onPasteShortcut = () => clipboardContent = 'copied by the user';
          final paster = DesktopPaster(controller);

          final outcome = await paster.paste(
            'hello',
            const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
          );

          expect(outcome, PasteOutcome.unconfirmedNoBridge);
          expect(controller.pasteCalls, 1);
          expect(clipboardContent, 'copied by the user');
        },
      );

      test(
        'a receipt timeout (unconfirmed) keeps the transcript on the clipboard instead of restoring',
        () async {
          clipboardContent = 'previous clipboard value';
          final bridge = _FakeReceiptBridge()
            ..onSystemClipboardWrite = (text) => clipboardContent = text;
          final paster = DesktopPaster(_FakeController(), receipts: bridge);

          final outcome = await paster.paste(
            'hello',
            const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
          );

          expect(outcome, PasteOutcome.unconfirmed);
          expect(bridge.restores, isEmpty);
          expect(clipboardContent, 'hello');
        },
      );
    },
  );

  group('DesktopPaster.paste — clipboard-history exclusion (issue #146)', () {
    test('falls back to Clipboard.setData for the transcript write when the '
        'native exclusion is unsupported (returns false)', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      // The transcript went through the native path first, then the plain
      // channel. Without a receipt it stays there (PAR-033).
      expect(controller.writeExcludingHistoryCalls, ['hello']);
      expect(clipboardContent, 'hello');
    });

    test('never touches Clipboard.setData when the native exclusion succeeds, '
        'and writes the transcript through the native call only', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController()
        ..writeExcludingHistoryResult = true
        ..onSystemClipboardWrite = (text) => clipboardContent = text;
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(controller.writeExcludingHistoryCalls, ['hello']);
      expect(clipboardContent, 'hello');
    });

    test(
      'does not clear the clipboard when there was no prior plain text '
      '(image/file content): the transcript stays, no blank restore',
      () async {
        clipboardContent = null;
        final controller = _FakeController();
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.unconfirmedNoBridge);
        expect(controller.writeExcludingHistoryCalls, ['hello']);
        expect(clipboardContent, 'hello');
      },
    );

    test('does not restore when the snapshot read fails', () async {
      final writes = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.getData':
                throw PlatformException(code: 'busy');
              case 'Clipboard.setData':
                writes.add((call.arguments as Map)['text'] as String);
                return null;
              default:
                return null;
            }
          });
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(controller.writeExcludingHistoryCalls, ['hello']);
      // Only the transcript went to the clipboard; no restore followed.
      expect(writes, ['hello']);
    });

    test('receipt path: no plain-text snapshot means the receipt is awaited '
        'but no blank restore is written', () async {
      clipboardContent = null;
      final controller = _FakeController();
      final receipts = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final paster = DesktopPaster(controller, receipts: receipts);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.success);
      expect(receipts.receiptWrites, ['hello']);
      expect(receipts.restores, isEmpty);
    });
  });

  group('DesktopPaster.paste — typing fallback restores the clipboard', () {
    test(
      'native paste fails, typing lands: unconfirmed, transcript kept on the clipboard',
      () async {
        clipboardContent = 'previous clipboard value';
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

        expect(outcome, PasteOutcome.unconfirmed);
        expect(controller.typeCalls, 1);
        expect(clipboardContent, 'hello');
      },
      skip: !Platform.isMacOS ? 'typing fallback is macOS only' : null,
    );
  });

  group('DesktopPaster.paste — Win+V leak diagnostics (issue #146)', () {
    late List<LogRecord> warnings;
    late StreamSubscription<LogRecord> sub;

    setUp(() {
      AppClipboard.transientWrites = SelfWriteSuppressionRegistry();
      warnings = <LogRecord>[];
      Logger.root.level = Level.ALL;
      sub = Logger.root.onRecord
          .where((r) => r.level >= Level.WARNING)
          .listen(warnings.add);
    });

    tearDown(() {
      sub.cancel();
    });

    test(
      'warns for the plain fallback write where a history-excluded '
      'write was expected (Windows), so a log shows the Win+V leak',
      () async {
        clipboardContent = 'previous clipboard value';
        final controller = _FakeController();
        final paster = DesktopPaster(controller, expectsHistoryExclusion: true);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.unconfirmedNoBridge);
        // The transcript write takes the plain path; nothing is restored.
        expect(warnings, hasLength(1));
        expect(warnings.map((r) => r.message), everyElement(contains('Win+V')));
      },
    );

    test('stays quiet where no history-excluded write exists '
        '(macOS/Linux)', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller, expectsHistoryExclusion: false);

      await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(warnings, isEmpty);
    });

    test('warns for each plain fallback write where a history-excluded write '
        'is expected, so a log shows where clipboard history may record the '
        'dictation', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final paster = DesktopPaster(controller, expectsHistoryExclusion: true);

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );
      await paster.copyOriginalToClipboard('original');

      // The transcript write and the undo copy are the two plain writes, and
      // each one warns.
      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(warnings, hasLength(2));
      expect(
        warnings.map((r) => r.message),
        everyElement(contains('clipboard history')),
      );
    });

    test('logs the plain fallback by default: a warning on Windows and macOS, '
        'an info line on Linux (the plain write is its only path)', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);

      await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      if (Platform.isLinux) {
        expect(warnings, isEmpty);
      } else {
        expect(warnings, isNotEmpty);
      }
    });

    test('marks the transcript as a transient write, so a later re-copy by '
        'another app can be recognized', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController()
        ..writeExcludingHistoryResult = true
        ..onSystemClipboardWrite = (text) => clipboardContent = text;
      final paster = DesktopPaster(controller);

      await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(warnings, isEmpty);
      expect(
        AppClipboard.transientWrites.shouldSuppress(
          ClipboardFingerprint.ofText('hello'),
        ),
        isTrue,
      );
    });

    // Win+V honors the Microsoft opt-out formats, but third-party clipboard
    // managers like Ditto 3.25 only skip writes carrying the older
    // "Clipboard Viewer Ignore" marker (reporter's finding on #146).
    test('Windows: transient writes also carry the Clipboard Viewer Ignore '
        'marker for third-party clipboard managers', () {
      final src = File(
        'windows/runner/desktop_paste_host.cpp',
      ).readAsStringSync();
      final start = src.indexOf('void ExcludeFromClipboardHistory()');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('\n}\n', start));
      for (final format in [
        'ExcludeClipboardContentFromMonitorProcessing',
        'CanIncludeInClipboardHistory',
        'CanUploadToCloudClipboard',
        'Clipboard Viewer Ignore',
      ]) {
        expect(body, contains('L"$format"'), reason: format);
      }
    });
  });

  group('DesktopPaster.typeText', () {
    test(
      'returns unconfirmed (keystrokes, no proof) and calls typeText once, not pasteClipboard',
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

        expect(outcome, PasteOutcome.unconfirmed);
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

    // Briefing B3 criterion 5: insert is never send. Typing "\n" arrives as a
    // Return keystroke that chat UIs read as "submit", so multi-line text is
    // refused here, not only on the paste() retry path.
    test(
      'refuses multi-line text and never types a Return (criterion 5)',
      () async {
        final controller = _FakeController()
          ..typeResult = const NativePasteResult(
            status: NativePasteStatus.success,
          );
        final paster = DesktopPaster(controller);

        for (final text in ['first\nsecond', 'first\rsecond']) {
          final outcome = await paster.typeText(
            text,
            const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
          );
          expect(outcome, PasteOutcome.failed, reason: 'text: $text');
        }
        expect(controller.typeCalls, 0);
      },
    );

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

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(controller.pasteCalls, 1);
      expect(controller.typeCalls, 0);
    });

    test('native paste fails: falls back to direct typing on macOS; '
        'stays failed on Windows and Linux, which skip the retry', () async {
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
      if (Platform.isMacOS) {
        expect(outcome, PasteOutcome.unconfirmed);
        expect(controller.typeCalls, 1);
      } else {
        expect(outcome, PasteOutcome.failed);
        expect(controller.typeCalls, 0);
      }
    });

    // P1.2: on Windows the "typing" path is clipboard + Ctrl+V again, and a
    // failed status can follow a partially injected burst. A retry would be
    // a second paste of the same transcript.
    test('only macOS retries a failed paste via typing', () {
      expect(typingFallbackAfterFailedPaste('macos'), isTrue);
      expect(typingFallbackAfterFailedPaste('windows'), isFalse);
      expect(typingFallbackAfterFailedPaste('linux'), isFalse);
    });

    for (final status in [
      NativePasteStatus.postFailed,
      NativePasteStatus.unknown,
    ]) {
      test('no second paste after an error status (${status.name}) without '
          'the typing fallback', () async {
        final controller = _FakeController()
          ..pasteResult = NativePasteResult(status: status)
          ..typeResult = const NativePasteResult(
            status: NativePasteStatus.success,
          );
        final paster = DesktopPaster(controller, typingFallback: false);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(controller.pasteCalls, 1);
        expect(controller.typeCalls, 0);
        expect(outcome, PasteOutcome.failed);
      });
    }

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

    // Briefing B3 criterion 1: the target app changed between recording start
    // and paste. The native side refuses; Dart must neither retype the text
    // into the new app (macOS/Windows typing fallback) nor restore the
    // clipboard, so the transcript stays available for a manual paste.
    test('a changed target is refused, keeps the transcript on the clipboard '
        'and is never retyped into the new app (criterion 1)', () async {
      final controller = _FakeController()
        ..pasteResult = const NativePasteResult(
          status: NativePasteStatus.targetChanged,
        )
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.success,
        );
      final paster = DesktopPaster(controller);
      clipboardContent = 'previous';

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.targetChanged);
      expect(controller.typeCalls, 0);
      expect(clipboardContent, 'hello');
    });

    // Briefing N12 / criterion 2: a sent paste shortcut is not proof. Only a
    // read receipt from the target proves the text was delivered.
    test('without a read receipt the paste is unconfirmed, not success, and '
        'the transcript stays on the clipboard (PAR-033)', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller);
      clipboardContent = 'previous';

      final outcome = await paster.paste(
        'hello',
        const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
      );

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(clipboardContent, 'hello');
    });

    test(
      'a target read receipt confirms the paste and restores the clipboard',
      () async {
        final controller = _FakeController();
        final receipts = _FakeReceiptBridge();
        final paster = DesktopPaster(controller, receipts: receipts);
        clipboardContent = 'previous';
        receipts.read.complete(ClipboardReadReceipt.read);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.success);
        expect(receipts.restores, ['previous']);
      },
    );

    test(
      'a receipt timeout is unconfirmed and does not restore the clipboard',
      () async {
        final controller = _FakeController();
        final receipts = _FakeReceiptBridge();
        final paster = DesktopPaster(controller, receipts: receipts);

        final outcome = await paster.paste(
          'hello',
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.unconfirmed);
        expect(receipts.restores, isEmpty);
      },
    );

    // Briefing N12: two dictations in quick succession must not interleave
    // their clipboard writes and restores (the second snapshot would otherwise
    // read the first transcript as the user's clipboard).
    test('overlapping pastes run one after the other', () async {
      final gate = Completer<void>();
      final controller = _FakeController()..firstPasteGate = gate;
      final paster = DesktopPaster(controller);
      const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

      final first = paster.paste('one', options);
      final second = paster.paste('two', options);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pasteCalls, 1, reason: 'second paste waits for first');

      gate.complete();
      await Future.wait([first, second]);
      expect(controller.pasteCalls, 2);
    });

    test('the native target_changed code maps to its own status', () {
      expect(
        NativePasteStatus.fromCode('target_changed'),
        NativePasteStatus.targetChanged,
      );
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

  group('DesktopPaster.paste — Zwischenablage nach dem Einfügen', () {
    const keep = PasteOptions(
      autoPasteDelayMs: 0,
      blocklist: '',
      restoreClipboardAfterPaste: false,
    );

    test(
      'keep: a confirmed paste leaves the dictation on the clipboard',
      () async {
        clipboardContent = 'previous clipboard value';
        final bridge = _FakeReceiptBridge()
          ..onSystemClipboardWrite = (text) {
            clipboardContent = text;
          };
        bridge.read.complete(ClipboardReadReceipt.read);
        final paster = DesktopPaster(_FakeController(), receipts: bridge);

        final outcome = await paster.paste('hello', keep);

        expect(outcome, PasteOutcome.success);
        expect(bridge.restores, isEmpty);
        expect(clipboardContent, 'hello');
      },
    );

    test(
      'keep: without a receipt bridge the dictation stays on the clipboard',
      () async {
        clipboardContent = 'previous clipboard value';
        final paster = DesktopPaster(_FakeController());

        final outcome = await paster.paste('hello', keep);

        expect(outcome, PasteOutcome.unconfirmedNoBridge);
        expect(clipboardContent, 'hello');
      },
    );

    test('keep: a receipt timeout keeps the transcript (unchanged)', () async {
      clipboardContent = 'previous clipboard value';
      final bridge = _FakeReceiptBridge()
        ..onSystemClipboardWrite = (text) => clipboardContent = text;
      final paster = DesktopPaster(_FakeController(), receipts: bridge);

      final outcome = await paster.paste('hello', keep);

      expect(outcome, PasteOutcome.unconfirmed);
      expect(bridge.restores, isEmpty);
      expect(clipboardContent, 'hello');
    });
  });

  group('DesktopPaster.paste — unreadable previous clipboard (RE2-15)', () {
    const restore = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

    test(
      'an unreadable (null) snapshot is never restored and raises the notice',
      () async {
        clipboardContent = null;
        final bridge = _FakeReceiptBridge()
          ..onSystemClipboardWrite = (text) {
            clipboardContent = text;
          };
        bridge.read.complete(ClipboardReadReceipt.read);
        var notices = 0;
        final paster = DesktopPaster(
          _FakeController(),
          receipts: bridge,
          onSnapshotUnavailable: () => notices++,
        );

        final outcome = await paster.paste('hello', restore);

        expect(outcome, PasteOutcome.success);
        expect(bridge.restores, isEmpty);
        expect(clipboardContent, 'hello');
        expect(notices, 1);
      },
    );

    test(
      'an empty snapshot is treated as unknown: no restore, notice raised',
      () async {
        clipboardContent = '';
        final bridge = _FakeReceiptBridge()
          ..onSystemClipboardWrite = (text) {
            clipboardContent = text;
          };
        bridge.read.complete(ClipboardReadReceipt.read);
        var notices = 0;
        final paster = DesktopPaster(
          _FakeController(),
          receipts: bridge,
          onSnapshotUnavailable: () => notices++,
        );

        await paster.paste('hello', restore);

        expect(bridge.restores, isEmpty);
        expect(notices, 1);
      },
    );

    test('no notice when the user chose to keep the dictation', () async {
      clipboardContent = null;
      final bridge = _FakeReceiptBridge()
        ..onSystemClipboardWrite = (text) {
          clipboardContent = text;
        };
      bridge.read.complete(ClipboardReadReceipt.read);
      var notices = 0;
      final paster = DesktopPaster(
        _FakeController(),
        receipts: bridge,
        onSnapshotUnavailable: () => notices++,
      );

      await paster.paste(
        'hello',
        const PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: '',
          restoreClipboardAfterPaste: false,
        ),
      );

      expect(notices, 0);
    });

    test('no notice when the previous clipboard was readable', () async {
      clipboardContent = 'previous clipboard value';
      final bridge = _FakeReceiptBridge()
        ..onSystemClipboardWrite = (text) {
          clipboardContent = text;
        };
      bridge.read.complete(ClipboardReadReceipt.read);
      var notices = 0;
      final paster = DesktopPaster(
        _FakeController(),
        receipts: bridge,
        onSnapshotUnavailable: () => notices++,
      );

      await paster.paste('hello', restore);

      expect(notices, 0);
    });
  });

  group('DesktopPaster.paste — no read receipt (receipts == null)', () {
    const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

    test('keeps the transcript on the clipboard, restore setting on or off '
        '(PAR-033)', () async {
      for (final restore in [true, false]) {
        clipboardContent = 'A';
        final paster = DesktopPaster(_FakeController());

        final outcome = await paster.paste(
          'B',
          PasteOptions(
            autoPasteDelayMs: 0,
            blocklist: '',
            restoreClipboardAfterPaste: restore,
          ),
        );

        expect(outcome, PasteOutcome.unconfirmedNoBridge);
        expect(clipboardContent, 'B', reason: 'restore=$restore');
      }
    });

    test('keeps a copy the user made during the paste window', () async {
      clipboardContent = 'A';
      final controller = _FakeController()
        ..onPasteShortcut = () => clipboardContent = 'C';
      final paster = DesktopPaster(controller);

      final outcome = await paster.paste('B', options);

      expect(outcome, PasteOutcome.unconfirmedNoBridge);
      expect(clipboardContent, 'C');
    });

    test(
      'without a previous plain-text clipboard the transcript stays',
      () async {
        clipboardContent = null;
        final paster = DesktopPaster(_FakeController());

        await paster.paste('B', options);

        expect(clipboardContent, 'B');
      },
    );
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
        clipboardContent = 'previous clipboard value';
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
      });
    });

    test('without a read receipt nothing is restored after the fixed buffer, '
        'and the outcome is unconfirmed', () {
      fakeAsync((async) {
        clipboardContent = 'previous clipboard value';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        PasteOutcome? outcome;
        paster.paste('hello', options).then((o) => outcome = o);
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 499));
        expect(outcome, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(outcome, PasteOutcome.unconfirmed);
        expect(bridge.restores, isEmpty);
      });
    });

    test('the timeout keeps the delay-dependent wait and never restores', () {
      fakeAsync((async) {
        clipboardContent = 'previous clipboard value';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        PasteOutcome? outcome;
        paster
            .paste(
              'hello',
              const PasteOptions(autoPasteDelayMs: 300, blocklist: ''),
            )
            .then((o) => outcome = o);
        async.flushMicrotasks();

        // max(500, 300 + 350) = 650 ms.
        async.elapse(const Duration(milliseconds: 649));
        expect(outcome, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(outcome, PasteOutcome.unconfirmed);
        expect(bridge.restores, isEmpty);
      });
    });

    test('never restores when another process took over the clipboard while '
        'waiting', () async {
      clipboardContent = 'previous clipboard value';
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.ownershipLost);
      final paster = DesktopPaster(_FakeController(), receipts: bridge);

      final outcome = await paster.paste('hello', options);

      expect(outcome, PasteOutcome.unconfirmed);
      expect(bridge.restores, isEmpty);
    });

    test('a not-owner restore result is not a paste failure', () async {
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read)
        ..restoreOutcome = ClipboardRestoreOutcome.notOwner;
      final paster = DesktopPaster(_FakeController(), receipts: bridge);

      expect(await paster.paste('hello', options), PasteOutcome.success);
    });

    test('falls back to the classic write and keeps the transcript when the '
        'receipt write is unavailable', () async {
      clipboardContent = 'previous clipboard value';
      final controller = _FakeController();
      final bridge = _FakeReceiptBridge()..writeResult = false;
      final paster = DesktopPaster(controller, receipts: bridge);

      final outcome = await paster.paste('hello', options);

      // The bridge exists but refused the write: a gap the user is told
      // about, unlike a platform without any bridge (Linux).
      expect(outcome, PasteOutcome.unconfirmedReceiptRefused);
      // Only the transcript write: no receipt, no restore (PAR-033).
      expect(controller.writeExcludingHistoryCalls, ['hello']);
      expect(bridge.restores, isEmpty);
      expect(clipboardContent, 'hello');
    });

    test(
      'a refused receipt write never restores the previous clipboard',
      () async {
        clipboardContent = 'previous clipboard value';
        final controller = _FakeController();
        final bridge = _FakeReceiptBridge()..writeResult = false;
        final paster = DesktopPaster(controller, receipts: bridge);

        await paster.paste('hello', options);

        expect(bridge.restores, isEmpty);
        expect(clipboardContent, isNot('previous clipboard value'));
        expect(clipboardContent, 'hello');
      },
    );

    test(
      'falls back to the classic path when the receipt write throws',
      () async {
        clipboardContent = 'previous clipboard value';
        final controller = _FakeController();
        final bridge = _FakeReceiptBridge()
          ..writeError = MissingPluginException('no handler');
        final paster = DesktopPaster(controller, receipts: bridge);

        expect(
          await paster.paste('hello', options),
          PasteOutcome.unconfirmedReceiptRefused,
        );
        expect(controller.writeExcludingHistoryCalls, ['hello']);
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

  group('DesktopPaster.paste — full clipboard snapshot (P1.1)', () {
    const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

    test('restore keeps the type: a saved image comes back through the '
        'native snapshot, not as text', () async {
      // An image has no plain-text form, so the old text-only path would
      // have dropped it.
      clipboardContent = null;
      final receipts = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final snapshots = _FakeSnapshotBridge();
      final paster = DesktopPaster(
        _FakeController(),
        receipts: receipts,
        snapshots: snapshots,
      );

      expect(await paster.paste('hello', options), PasteOutcome.success);
      expect(snapshots.snapshots, 1);
      expect(snapshots.restores, 1);
      expect(receipts.restores, isEmpty);
      expect(snapshots.discards, 0);
    });

    test(
      'rich content with a text form is restored natively as a whole',
      () async {
        clipboardContent = 'plain form';
        final receipts = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final snapshots = _FakeSnapshotBridge()
          ..snapshot = const ClipboardSnapshot(
            ClipboardSnapshotStatus.saved,
            text: 'plain form',
            formats: 3,
            bytes: 900,
          );
        final paster = DesktopPaster(
          _FakeController(),
          receipts: receipts,
          snapshots: snapshots,
        );

        expect(await paster.paste('hello', options), PasteOutcome.success);
        expect(snapshots.restores, 1);
        expect(receipts.restores, isEmpty);
      },
    );

    test('no restore after the clipboard changed while waiting', () async {
      final receipts = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.ownershipLost);
      final snapshots = _FakeSnapshotBridge();
      final paster = DesktopPaster(
        _FakeController(),
        receipts: receipts,
        snapshots: snapshots,
      );

      expect(await paster.paste('hello', options), PasteOutcome.unconfirmed);
      expect(snapshots.restores, 0);
      expect(receipts.restores, isEmpty);
      // The unused snapshot is dropped.
      expect(snapshots.discards, 1);
    });

    test('a clipboard changed after the read is reported by the host and '
        'never falls back to a text restore', () async {
      clipboardContent = 'previous';
      final receipts = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final snapshots = _FakeSnapshotBridge()
        ..snapshot = const ClipboardSnapshot(
          ClipboardSnapshotStatus.saved,
          text: 'previous',
        )
        ..restoreOutcome = ClipboardRestoreOutcome.notOwner;
      final paster = DesktopPaster(
        _FakeController(),
        receipts: receipts,
        snapshots: snapshots,
      );

      expect(await paster.paste('hello', options), PasteOutcome.success);
      expect(snapshots.restores, 1);
      expect(receipts.restores, isEmpty);
    });

    test(
      'a failed native snapshot falls back to the plain-text restore',
      () async {
        clipboardContent = 'previous clipboard value';
        final receipts = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final snapshots = _FakeSnapshotBridge()
          ..snapshot = const ClipboardSnapshot(ClipboardSnapshotStatus.failed);
        final paster = DesktopPaster(
          _FakeController(),
          receipts: receipts,
          snapshots: snapshots,
        );

        expect(await paster.paste('hello', options), PasteOutcome.success);
        expect(snapshots.restores, 0);
        expect(receipts.restores, ['previous clipboard value']);
      },
    );

    for (final status in [
      ClipboardSnapshotStatus.empty,
      ClipboardSnapshotStatus.denied,
    ]) {
      test('an ${status.name} snapshot restores nothing and reports the '
          'unsaved clipboard', () async {
        var unavailable = 0;
        final receipts = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final snapshots = _FakeSnapshotBridge()
          ..snapshot = ClipboardSnapshot(status);
        final paster = DesktopPaster(
          _FakeController(),
          receipts: receipts,
          snapshots: snapshots,
          onSnapshotUnavailable: () => unavailable++,
        );

        expect(await paster.paste('hello', options), PasteOutcome.success);
        expect(snapshots.restores, 0);
        expect(receipts.restores, isEmpty);
        expect(unavailable, 1);
      });
    }

    test(
      'the clipboard setting that keeps the transcript drops the snapshot',
      () async {
        final receipts = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final snapshots = _FakeSnapshotBridge();
        final paster = DesktopPaster(
          _FakeController(),
          receipts: receipts,
          snapshots: snapshots,
        );

        expect(
          await paster.paste(
            'hello',
            const PasteOptions(
              autoPasteDelayMs: 0,
              blocklist: '',
              restoreClipboardAfterPaste: false,
            ),
          ),
          PasteOutcome.success,
        );
        expect(snapshots.restores, 0);
        expect(snapshots.discards, 1);
      },
    );
  });

  group('DesktopPaster undo bridge (DEV-165, DEV-185)', () {
    const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

    // A paste counts as an insert only with the target's read receipt
    // (briefing N12). A completed read is returned on every wait, so one
    // bridge serves several pastes.
    _FakeReceiptBridge confirmingBridge() =>
        _FakeReceiptBridge()..read.complete(ClipboardReadReceipt.read);

    test(
      'a clean native paste sets the serial, a second paste replaces it',
      () async {
        final paster = DesktopPaster(
          _FakeController(),
          receipts: confirmingBridge(),
        );
        expect(paster.cleanPasteSerial, isNull);

        await paster.paste('one', options);
        final first = paster.cleanPasteSerial;
        await paster.paste('two', options);

        expect(first, isNotNull);
        expect(paster.cleanPasteSerial, isNot(first));
      },
    );

    test('a failed paste clears the serial', () async {
      final controller = _FakeController();
      final paster = DesktopPaster(controller, receipts: confirmingBridge());
      await paster.paste('one', options);
      expect(paster.cleanPasteSerial, isNotNull);

      controller.pasteResult = const NativePasteResult(
        status: NativePasteStatus.postFailed,
      );
      final outcome = await paster.paste('two', options);

      expect(outcome, isNot(PasteOutcome.success));
      expect(paster.cleanPasteSerial, isNull);
    });

    test('recording start (prime) clears the serial', () async {
      final paster = DesktopPaster(_FakeController());
      await paster.paste('one', options);

      await paster.prime();

      expect(paster.cleanPasteSerial, isNull);
    });

    test('a typed insert clears the serial', () async {
      final controller = _FakeController()
        ..typeResult = const NativePasteResult(
          status: NativePasteStatus.success,
        );
      final paster = DesktopPaster(controller, receipts: confirmingBridge());
      await paster.paste('one', options);
      expect(paster.cleanPasteSerial, isNotNull);

      final outcome = await paster.typeText('two', options);

      // Typed keystrokes have no receipt, so the outcome is unconfirmed.
      expect(outcome, PasteOutcome.unconfirmed);
      expect(paster.cleanPasteSerial, isNull);
    });

    test(
      'a paste that lands only through the typing fallback is not clean',
      () async {
        final controller = _FakeController()
          ..pasteResult = const NativePasteResult(
            status: NativePasteStatus.postFailed,
          )
          ..typeResult = const NativePasteResult(
            status: NativePasteStatus.success,
          );
        final paster = DesktopPaster(controller, typingFallback: true);

        final outcome = await paster.paste('one', options);

        // Typing has no read receipt: the fallback lands unconfirmed (N12).
        expect(outcome, PasteOutcome.unconfirmed);
        expect(controller.typeCalls, 1);
        expect(paster.cleanPasteSerial, isNull);
      },
    );

    test(
      'without the channel the input check answers unknown (counts as typed)',
      () async {
        final paster = DesktopPaster(_FakeController());

        final snapshot = await paster.inputIdleSnapshot();
        expect(snapshot, isNull);
        expect(userInputSince(const Duration(seconds: 1), snapshot), isTrue);
        expect(await paster.sendUndoShortcut(), isFalse);
      },
    );

    test(
      'the original text goes through the transient history-excluded write',
      () async {
        final controller = _FakeController()
          ..writeExcludingHistoryResult = true;
        final paster = DesktopPaster(controller);

        final copied = await paster.copyOriginalToClipboard('Original');

        expect(copied, isTrue);
        expect(controller.writeExcludingHistoryCalls, ['Original']);
      },
    );
  });

  group('DesktopPaster copy path on macOS (BIZ-61)', () {
    const channel = MethodChannel('com.whispaste.desktop_paste');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    void mockPlatform(
      Future<Object?> Function(MethodCall call) handler,
      List<String> plainClipboardWrites,
    ) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, handler);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          plainClipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    }

    test(
      'the copy goes through the native transient write, never '
      'Clipboard.setData',
      skip: !Platform.isMacOS,
      () async {
        final channelCalls = <String>[];
        final plainWrites = <String>[];
        mockPlatform((call) async {
          channelCalls.add(call.method);
          return call.method == 'writeClipboardText' ? true : null;
        }, plainWrites);

        final paster = DesktopPaster(MacOSDesktopPasteController());
        final copied = await paster.copyOriginalToClipboard('Original');

        expect(copied, isTrue);
        expect(channelCalls, contains('writeClipboardText'));
        expect(plainWrites, isEmpty);
      },
    );

    test(
      'a failed native write is logged as a warning and never silent',
      skip: !Platform.isMacOS,
      () async {
        final warnings = <LogRecord>[];
        Logger.root.level = Level.ALL;
        final sub = Logger.root.onRecord
            .where((r) => r.level >= Level.WARNING)
            .listen(warnings.add);
        addTearDown(sub.cancel);
        final plainWrites = <String>[];
        mockPlatform((call) async {
          if (call.method == 'writeClipboardText') {
            // A failed write, not a missing handler: the missing-handler case
            // trips the debug assert in ChannelDesktopPasteController (GS-106).
            throw PlatformException(code: 'write_failed');
          }
          return null;
        }, plainWrites);

        final paster = DesktopPaster(MacOSDesktopPasteController());
        await paster.copyOriginalToClipboard('Original');

        expect(warnings, isNotEmpty);
        expect(
          warnings.map((r) => r.message),
          everyElement(contains('clipboard history')),
        );
      },
    );
  });
  // XP-6-06: the block list had no effect on Windows and Linux, because only
  // macOS reported a target. Windows reports the exe base name, Linux the X11
  // WM_CLASS; both must match the list exactly like a macOS bundle id.
  group('block list matches the target app on every platform', () {
    const cases = [
      (name: 'Windows exe', target: 'notepad', entry: 'notepad.exe'),
      (
        name: 'Windows exe, other case',
        target: 'WindowsTerminal',
        entry: 'windowsterminal',
      ),
      (name: 'Linux WM_CLASS', target: 'google-chrome', entry: 'google-chrome'),
    ];
    for (final c in cases) {
      test(
        '${c.name}: a listed target is blocked and nothing is pasted',
        () async {
          final controller = _FakeController()..bundleIdToReturn = c.target;
          final outcome = await DesktopPaster(controller).paste(
            'hello',
            PasteOptions(autoPasteDelayMs: 0, blocklist: c.entry),
          );

          expect(outcome, PasteOutcome.blocked);
          expect(controller.pasteCalls, 0);
        },
      );

      test('${c.name}: an unlisted target still pastes', () async {
        final controller = _FakeController()..bundleIdToReturn = c.target;
        final outcome = await DesktopPaster(controller).paste(
          'hello',
          const PasteOptions(
            autoPasteDelayMs: 0,
            blocklist: 'some-other-app',
            copyBlockedToClipboard: false,
          ),
        );

        expect(outcome, isNot(PasteOutcome.blocked));
        expect(controller.pasteCalls, 1);
      });
    }

    test(
      'Wayland or any unknown target fails closed while the list is set',
      () async {
        final controller = _FakeController()..bundleIdToReturn = null;
        final outcome = await DesktopPaster(controller).paste(
          'hello',
          const PasteOptions(
            autoPasteDelayMs: 0,
            blocklist: 'notepad.exe',
            copyBlockedToClipboard: false,
          ),
        );

        expect(outcome, PasteOutcome.blocked);
        expect(controller.pasteCalls, 0);
      },
    );
  });

  group('DesktopPaster — Quittung, Schalter und Secure Input (W-E1)', () {
    const options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');
    const legacy = PasteOptions(
      autoPasteDelayMs: 0,
      blocklist: '',
      restoreClipboardWithoutReceipt: true,
    );

    test(
      'a confirmed read restores the previous clipboard and succeeds',
      () async {
        clipboardContent = 'previous';
        final bridge = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final paster = DesktopPaster(_FakeController(), receipts: bridge);

        expect(await paster.paste('hello', legacy), PasteOutcome.success);
        expect(bridge.restores, ['previous']);
      },
    );

    test('switch off: a timeout keeps the transcript and restores nothing', () {
      fakeAsync((async) {
        clipboardContent = 'previous';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        PasteOutcome? outcome;
        paster.paste('hello', options).then((o) => outcome = o);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        expect(outcome, PasteOutcome.unconfirmed);
        expect(bridge.restores, isEmpty);
      });
    });

    test('switch on: a timeout restores after the fixed wait, outcome stays '
        'unconfirmed', () {
      fakeAsync((async) {
        clipboardContent = 'previous';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        PasteOutcome? outcome;
        paster.paste('hello', legacy).then((o) => outcome = o);
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 499));
        expect(bridge.restores, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(bridge.restores, ['previous']);
        expect(outcome, PasteOutcome.unconfirmed);
      });
    });

    test('switch on: a takeover of the clipboard restores nothing', () {
      fakeAsync((async) {
        clipboardContent = 'previous';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        PasteOutcome? outcome;
        paster.paste('hello', legacy).then((o) => outcome = o);
        async.flushMicrotasks();

        bridge.read.complete(ClipboardReadReceipt.ownershipLost);
        async.elapse(const Duration(seconds: 2));

        expect(outcome, PasteOutcome.unconfirmed);
        expect(bridge.restores, isEmpty);
      });
    });

    test('switch on but clipboard restore off: nothing is restored', () {
      fakeAsync((async) {
        clipboardContent = 'previous';
        final bridge = _FakeReceiptBridge();
        final paster = DesktopPaster(_FakeController(), receipts: bridge);
        const keep = PasteOptions(
          autoPasteDelayMs: 0,
          blocklist: '',
          restoreClipboardAfterPaste: false,
          restoreClipboardWithoutReceipt: true,
        );
        paster.paste('hello', keep);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        expect(bridge.restores, isEmpty);
      });
    });

    test('secure input active: no paste is sent, the transcript is written '
        'to the clipboard and the outcome is secureInput', () async {
      final controller = _SecureInputController(SecureInputState.active);
      final bridge = _FakeReceiptBridge();
      final paster = DesktopPaster(controller, receipts: bridge);

      final outcome = await paster.paste('hello', options);

      expect(outcome, PasteOutcome.secureInput);
      expect(controller.probeCalls, 1);
      expect(controller.pasteCalls, 0);
      expect(controller.typeCalls, 0);
      expect(bridge.receiptWrites, isEmpty);
      expect(controller.writeExcludingHistoryCalls, ['hello']);
    });

    test('secure input inactive: the paste runs as before', () async {
      final controller = _SecureInputController(SecureInputState.inactive);
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final paster = DesktopPaster(controller, receipts: bridge);

      expect(await paster.paste('hello', options), PasteOutcome.success);
      expect(controller.pasteCalls, 1);
    });

    test(
      'secure input unsupported (Windows, Linux): the paste runs as before',
      () async {
        final controller = _SecureInputController(SecureInputState.unsupported);
        final bridge = _FakeReceiptBridge()
          ..read.complete(ClipboardReadReceipt.read);
        final paster = DesktopPaster(controller, receipts: bridge);

        expect(await paster.paste('hello', options), PasteOutcome.success);
        expect(controller.pasteCalls, 1);
      },
    );

    test('a failing secure input probe counts as inactive', () async {
      final controller = _SecureInputController(
        SecureInputState.active,
        probeError: StateError('channel down'),
      );
      final bridge = _FakeReceiptBridge()
        ..read.complete(ClipboardReadReceipt.read);
      final paster = DesktopPaster(controller, receipts: bridge);

      expect(await paster.paste('hello', options), PasteOutcome.success);
      expect(controller.pasteCalls, 1);
    });
  });
}

/// A controller that also answers the secure input probe (macOS only).
class _SecureInputController extends _FakeController
    implements SecureInputProbe {
  _SecureInputController(this.state, {this.probeError});

  final SecureInputState state;
  final Object? probeError;
  int probeCalls = 0;

  @override
  Future<SecureInputState> secureInputState() async {
    probeCalls++;
    if (probeError != null) throw probeError!;
    return state;
  }

  @override
  Future<SecureInputHolder?> secureInputHolder() async => null;
}
