import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/clipboard_history/app_clipboard.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_entry.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_provider.dart';
import 'package:whispaste/services/clipboard_history/self_write_suppression_registry.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/side_panel/side_panel_controller_interface.dart';
import 'package:whispaste/services/side_panel/side_panel_controller_provider.dart';
import 'package:whispaste/services/side_panel/side_panel_events.dart';
import 'package:whispaste/services/side_panel/side_panel_service.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

class _FakeDesktopPasteController implements DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;
  bool pasteSucceeds = true;

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls += 1;
    return true;
  }

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls += 1;
    return NativePasteResult(
      status: pasteSucceeds
          ? NativePasteStatus.success
          : NativePasteStatus.postFailed,
    );
  }

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async => const NativePasteResult(status: NativePasteStatus.postFailed);

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<void> dispose() async {}
}

class _FakeSidePanelController implements SidePanelController {
  final snapshots = <SidePanelSnapshot>[];
  bool disposed = false;
  final _eventsController = StreamController<SidePanelEvent>.broadcast();

  @override
  Future<void> updateSnapshot(SidePanelSnapshot snapshot) async {
    snapshots.add(snapshot);
  }

  @override
  Stream<SidePanelEvent> get events => _eventsController.stream;

  void fireEvent(SidePanelEvent event) => _eventsController.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventsController.close();
  }
}

/// Reads the notifier while retaining a live listener on the provider.
///
/// [sidePanelServiceProvider] is a plain (non-keepAlive) `NotifierProvider`;
/// in production it stays alive because `WpServiceBootstrap` watches it for
/// the app's lifetime. A bare `container.read(...)` here has no such
/// watcher, so under Riverpod 3's auto-dispose-by-default the element (and
/// the `ref.listen` subscriptions its `onControllerReady` sets up on
/// `historyEntriesProvider`/`snippetsProvider`) would be torn down again
/// right after this synchronous read returns -- before `open()`'s awaited
/// `.future` reads ever resolve.
SidePanelService _readService(ProviderContainer c) {
  c.listen(sidePanelServiceProvider, (_, _) {});
  return c.read(sidePanelServiceProvider.notifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HistoryDatabase db;
  late _FakeDesktopPasteController fakeDesktopPaste;
  late _FakeSidePanelController fakePanel;
  late ProviderContainer container;
  late String? clipboardText;
  late List<String?> clipboardWrites;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) => db),
      desktopPasteControllerProvider.overrideWith((ref) => fakeDesktopPaste),
      sidePanelControllerProvider.overrideWith((ref) => fakePanel),
    ],
  );

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    fakeDesktopPaste = _FakeDesktopPasteController();
    fakePanel = _FakeSidePanelController();
    clipboardText = null;
    clipboardWrites = [];
    AppClipboard.registry = SelfWriteSuppressionRegistry();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = args['text'] as String?;
              clipboardWrites.add(clipboardText);
              return null;
            case 'Clipboard.getData':
              if (clipboardText == null) return null;
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('SidePanelService.open/close', () {
    test(
      'open() captures the paste target and shows a visible snapshot',
      () async {
        container = buildContainer();
        await _readService(container).open();

        expect(fakeDesktopPaste.captureCalls, 1);
        expect(fakePanel.snapshots.last.visible, isTrue);
      },
    );

    test('close() hides the panel without re-priming', () async {
      container = buildContainer();
      final service = _readService(container);
      await service.open();
      await service.close();

      expect(fakeDesktopPaste.captureCalls, 1);
      expect(fakePanel.snapshots.last.visible, isFalse);
    });

    test(
      'the native sensor strip firing hoverEntered opens the panel',
      () async {
        container = buildContainer();
        _readService(container);
        fakePanel.fireEvent(const SidePanelHoverEntered());
        await Future<void>.delayed(Duration.zero);

        expect(fakeDesktopPaste.captureCalls, 1);
        expect(fakePanel.snapshots.last.visible, isTrue);
      },
    );

    test('hoverLeft from the panel itself closes it', () async {
      container = buildContainer();
      final service = _readService(container);
      await service.open();
      fakePanel.fireEvent(const SidePanelHoverLeft());
      await Future<void>.delayed(Duration.zero);

      expect(fakePanel.snapshots.last.visible, isFalse);
    });
  });

  group('SidePanelService row activation', () {
    test(
      'clicking a transcription row pastes its content and closes',
      () async {
        container = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) => db),
            desktopPasteControllerProvider.overrideWith(
              (ref) => fakeDesktopPaste,
            ),
            sidePanelControllerProvider.overrideWith((ref) => fakePanel),
            historyEntriesProvider.overrideWith(
              (ref) => Stream.value([_historyEntry()]),
            ),
          ],
        );
        // No manual pre-warm here on purpose: open() itself now awaits the
        // history stream's first value (see the cold-start test below), so
        // this test also doubles as end-to-end proof that guard works.
        final service = _readService(container);
        await service.open();

        fakePanel.fireEvent(
          const SidePanelRowClicked(SidePanelSection.transcriptions, 'entry-1'),
        );
        // DesktopPaster.paste() enforces a real >=500ms floor before
        // restoring the clipboard and resolving (see desktop_paster.dart
        // step 5) -- wait past it with margin instead of Duration.zero.
        await Future<void>.delayed(const Duration(milliseconds: 800));

        expect(fakeDesktopPaste.pasteCalls, 1);
        // The clipboard is restored to its previous (empty) content once
        // the paste lands, so check the write happened rather than the
        // final resting value.
        expect(clipboardWrites, contains('Hello from history'));
        expect(fakePanel.snapshots.last.visible, isFalse);
      },
    );

    test('clicking a snippet row pastes its body', () async {
      container = buildContainer();
      await container.read(snippetsProvider.notifier).add('Sig', 'Best, Me');
      final snippetId = container.read(snippetsProvider).value!.single.id;

      final service = _readService(container);
      await service.open();

      fakePanel.fireEvent(
        SidePanelRowClicked(SidePanelSection.snippets, snippetId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeDesktopPaste.pasteCalls, 1);
      expect(clipboardText, 'Best, Me');
    });

    test(
      'clicking a clipboard-history row pastes its text and marks self-write suppression',
      () async {
        container = buildContainer();
        container
            .read(clipboardHistoryProvider.notifier)
            .add(
              ClipboardHistoryEntry.text(
                'copied earlier',
                capturedAt: DateTime(2026),
              ),
            );

        final service = _readService(container);
        await service.open();

        fakePanel.fireEvent(
          const SidePanelRowClicked(
            SidePanelSection.clipboardHistory,
            'clip-0',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(clipboardText, 'copied earlier');
        // End-to-end proof the suppression design holds at the panel layer:
        // AppClipboard.setText (called inside DesktopPaster.paste) marked
        // the registry for exactly the content that was just pasted.
        expect(
          AppClipboard.registry.shouldSuppress(
            ClipboardFingerprint.ofText('copied earlier'),
          ),
          isTrue,
        );
      },
    );

    test('open() waits for a slow-to-resolve history stream instead of '
        'showing an empty panel that pops in a moment later', () async {
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          sidePanelControllerProvider.overrideWith((ref) => fakePanel),
          historyEntriesProvider.overrideWith(
            (ref) => Stream.fromFuture(
              Future.delayed(
                const Duration(milliseconds: 50),
                () => [_historyEntry()],
              ),
            ),
          ),
        ],
      );
      final service = _readService(container);
      await service.open();

      expect(
        fakePanel.snapshots.last.transcriptions,
        isNotEmpty,
        reason:
            'open() must resolve the history stream before showing the '
            'panel, not read its still-loading value',
      );
    });

    test("transcription rows carry the entry's persisted color slot", () async {
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          sidePanelControllerProvider.overrideWith((ref) => fakePanel),
          historyEntriesProvider.overrideWith(
            (ref) => Stream.value([_historyEntry()]),
          ),
        ],
      );
      final service = _readService(container);
      await service.open();

      expect(
        fakePanel.snapshots.last.transcriptions.single.colorSlot,
        _historyEntry().colorSlot,
        reason:
            "the row's avatar disc must match the same entry's avatar in "
            'the main window, which reads this persisted slot',
      );
    });

    test('transcription and snippet rows carry the full insertable content, '
        'not just the (possibly shorter) display title', () async {
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          sidePanelControllerProvider.overrideWith((ref) => fakePanel),
          historyEntriesProvider.overrideWith(
            (ref) => Stream.value([
              _historyEntry().copyWith(
                title: 'Short label',
                content: 'The full, unabridged transcript body.',
              ),
            ]),
          ),
        ],
      );
      await container.read(snippetsProvider.future);
      await container
          .read(snippetsProvider.notifier)
          .add('Greeting', 'Hello, full snippet body here.');
      final service = _readService(container);
      await service.open();

      final snapshot = fakePanel.snapshots.last;
      expect(
        snapshot.transcriptions.single.content,
        'The full, unabridged transcript body.',
      );
      expect(
        snapshot.snippets.single.content,
        'Hello, full snippet body here.',
      );
    });

    test('an unresolved row id does not paste anything', () async {
      container = buildContainer();
      final service = _readService(container);
      await service.open();

      fakePanel.fireEvent(
        const SidePanelRowClicked(SidePanelSection.transcriptions, 'nope'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeDesktopPaste.pasteCalls, 0);
    });
  });
}

HistoryEntry _historyEntry() => HistoryEntry(
  id: 'entry-1',
  content: 'Hello from history',
  title: '',
  timestamp: DateTime(2026, 1, 1, 12),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);
