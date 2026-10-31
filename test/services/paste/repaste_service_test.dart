import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/paste/repaste_service.dart';

class _InMemorySettings extends SettingsNotifier {
  _InMemorySettings(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

class _RecordingPaster implements Paster {
  final pasted = <(String, PasteOptions)>[];

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    pasted.add((text, options));
    return PasteOutcome.success;
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.success;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}

/// Hand-off test: the "paste the last dictation again" hotkey reaches the
/// shared paster with the user's paste options, and never during a
/// recording.
void main() {
  late HistoryDatabase db;
  late _RecordingPaster paster;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    paster = _RecordingPaster();
  });
  tearDown(() => db.close());

  Future<ProviderContainer> container({
    RecordingPhase phase = RecordingPhase.idle,
    AppSettings settings = const AppSettings(),
  }) async {
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _InMemorySettings(settings)),
        recordingPhaseProvider.overrideWith((ref) => phase),
        historyDatabaseProvider.overrideWithValue(db),
        pasterProvider.overrideWithValue(paster),
      ],
    );
    addTearDown(c.dispose);
    await c.read(settingsProvider.future);
    return c;
  }

  Future<void> addEntry(
    String id,
    String content,
    DateTime at, {
    bool pinned = false,
    String? edited,
  }) => db.insertHistoryEntry(
    HistoryEntriesCompanion(
      id: Value(id),
      content: Value(content),
      timestamp: Value(at),
      pinned: Value(pinned),
      smartModeEditedContent: Value(edited),
    ),
  );

  test('the dictation of this session wins, with the paste options', () async {
    await addEntry('a', 'saved', DateTime(2026, 10, 30, 9));
    final c = await container(
      settings: const AppSettings(
        behavior: BehaviorSettings(
          autoPasteDelay: 350,
          autoPasteBlocklist: 'com.example.vault',
        ),
      ),
    );
    c.read(lastDictationTextProvider.notifier).set('just dictated');

    expect(
      await c.read(repasteServiceProvider).pasteLast(),
      PasteOutcome.success,
    );
    final (text, options) = paster.pasted.single;
    expect(text, 'just dictated');
    expect(options.autoPasteDelayMs, 350);
    expect(options.blocklist, 'com.example.vault');
  });

  test('after a restart it takes the newest recording as shown, pins do not '
      'count', () async {
    await addEntry('old', 'old pinned', DateTime(2026, 10, 1), pinned: true);
    await addEntry(
      'new',
      'raw',
      DateTime(2026, 10, 30),
      edited: 'edited by Smart Mode',
    );
    final c = await container();

    await c.read(repasteServiceProvider).pasteLast();

    expect(paster.pasted.single.$1, 'edited by Smart Mode');
  });

  test('with saving off a blocked paste still leaves the text on the '
      'clipboard', () async {
    final c = await container(
      settings: const AppSettings(
        behavior: BehaviorSettings(copyBlockedToClipboard: false),
        history: HistorySettings(saveHistory: false),
      ),
    );
    c.read(lastDictationTextProvider.notifier).set('kept');

    await c.read(repasteServiceProvider).pasteLast();

    expect(paster.pasted.single.$2.copyBlockedToClipboard, isTrue);
  });

  test(
    'does nothing during a recording; without any dictation it says so',
    () async {
      await addEntry('a', 'saved', DateTime(2026, 10, 30));
      final recording = await container(phase: RecordingPhase.recording);
      expect(await recording.read(repasteServiceProvider).pasteLast(), isNull);

      expect(recording.read(repasteEmptyNoticeProvider), 0);

      await db.delete(db.historyEntries).go();
      final empty = await container();
      expect(await empty.read(repasteServiceProvider).pasteLast(), isNull);
      expect(paster.pasted, isEmpty);
      // Nothing to paste is never silent: the overlay notice is raised.
      expect(empty.read(repasteEmptyNoticeProvider), 1);
    },
  );

  test('the hotkey is off by default and its settings round-trip', () {
    expect(AppSettings.defaults.behavior.repasteHotkeyEnabled, isFalse);
    const on = BehaviorSettings(
      repasteHotkeyEnabled: true,
      repasteHotkeyKey: 'R',
      repasteHotkeyKeyDisplay: 'R',
      repasteHotkeyModifiers: 'ctrl+alt',
    );
    expect(BehaviorSettings.fromMap(on.toMap()), on);
  });
}
