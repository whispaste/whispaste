import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/selection_edit/selection_undo.dart';

/// A paster with the undo bridge. Every condition of the keystroke gate can
/// be set from the test (DEV-165, DEV-185).
class _UndoPaster implements Paster, UndoKeystrokeSender {
  _UndoPaster({
    this.frontmost = 'com.example.editor',
    this.cleanSerial = 1,
    this.typed = false,
    this.clicked = false,
    this.keystrokeWorks = true,
    this.copyWorks = true,
  });

  String? frontmost;
  int? cleanSerial;

  /// Whether the native snapshot reports a key typed after the insert.
  final bool typed;

  /// Whether the native snapshot reports a click after the insert (GS-056).
  final bool clicked;
  final bool keystrokeWorks;
  final bool copyWorks;

  int keystrokes = 0;
  final copied = <String>[];
  int snapshotCalls = 0;

  @override
  int? get cleanPasteSerial => cleanSerial;

  @override
  Future<InputIdleSnapshot?> inputIdleSnapshot() async {
    snapshotCalls++;
    // A key just went down (idle 0 s) that is not our synthetic one.
    return InputIdleSnapshot(
      keyIdle: typed ? 0 : 1e9,
      mouseIdle: clicked ? 0 : 1e9,
      syntheticIdle: 1e9,
    );
  }

  @override
  Future<bool> sendUndoShortcut() async {
    keystrokes++;
    return keystrokeWorks;
  }

  @override
  Future<bool> copyOriginalToClipboard(String text) async {
    copied.add(text);
    return copyWorks;
  }

  @override
  Future<String?> getTargetBundleId() async => frontmost;

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      PasteOutcome.success;

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.failed;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);
}

/// A paster without the undo bridge (test doubles, unsupported platforms).
class _PlainPaster implements Paster {
  @override
  Future<String?> getTargetBundleId() async => 'com.example.editor';

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      PasteOutcome.success;

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.failed;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);
}

SelectionUndoTicket _ticket({int? insertSerial = 1}) => SelectionUndoTicket(
  originalText: 'Ich habe Müller gesehen.',
  targetBundleId: 'com.example.editor',
  insertSerial: insertSerial,
  sinceInsert: Stopwatch()..start(),
);

void main() {
  test('the keystroke undoes the edit when every condition holds', () async {
    final paster = _UndoPaster();

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.keystrokeSent);
    expect(paster.keystrokes, 1);
    expect(paster.copied, isEmpty);
    expect(paster.snapshotCalls, 1);
  });

  test(
    'another app in front gets no keystroke; the original is copied',
    () async {
      final paster = _UndoPaster(frontmost: 'com.example.other');

      final outcome = await undoSelectionEdit(
        ticket: _ticket(),
        paster: paster,
      );

      expect(outcome, SelectionUndoOutcome.copiedToClipboard);
      expect(paster.keystrokes, 0);
      expect(paster.copied.single, 'Ich habe Müller gesehen.');
    },
  );

  test('no frontmost app known: no keystroke', () async {
    final paster = _UndoPaster(frontmost: null);

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.copiedToClipboard);
    expect(paster.keystrokes, 0);
  });

  test(
    'a later insert or recording start (new serial) blocks the keystroke',
    () async {
      final paster = _UndoPaster(cleanSerial: 2);

      final outcome = await undoSelectionEdit(
        ticket: _ticket(),
        paster: paster,
      );

      expect(outcome, SelectionUndoOutcome.copiedToClipboard);
      expect(paster.keystrokes, 0);
    },
  );

  test(
    'a cleared serial (recording started, no clean paste since) blocks the keystroke',
    () async {
      final paster = _UndoPaster(cleanSerial: null);

      final outcome = await undoSelectionEdit(
        ticket: _ticket(),
        paster: paster,
      );

      expect(outcome, SelectionUndoOutcome.copiedToClipboard);
      expect(paster.keystrokes, 0);
    },
  );

  test(
    'an insert that was typed (no serial on the ticket) blocks the keystroke',
    () async {
      final paster = _UndoPaster();

      final outcome = await undoSelectionEdit(
        ticket: _ticket(insertSerial: null),
        paster: paster,
      );

      expect(outcome, SelectionUndoOutcome.copiedToClipboard);
      expect(paster.keystrokes, 0);
    },
  );

  test('a click after the insert blocks the keystroke (GS-056)', () async {
    final paster = _UndoPaster(clicked: true);

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.copiedToClipboard);
    expect(paster.keystrokes, 0);
  });

  test('a key typed after the insert blocks the keystroke', () async {
    final paster = _UndoPaster(typed: true);

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.copiedToClipboard);
    expect(paster.keystrokes, 0);
    expect(paster.copied.single, 'Ich habe Müller gesehen.');
  });

  test('a failing keystroke falls back to copying the original', () async {
    final paster = _UndoPaster(keystrokeWorks: false);

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.copiedToClipboard);
    expect(paster.keystrokes, 1);
    expect(paster.copied.single, 'Ich habe Müller gesehen.');
  });

  test('a failed clipboard write reports failure, not success', () async {
    final paster = _UndoPaster(
      frontmost: 'com.example.other',
      copyWorks: false,
    );

    final outcome = await undoSelectionEdit(ticket: _ticket(), paster: paster);

    expect(outcome, SelectionUndoOutcome.failed);
  });

  test('a paster without the undo bridge cannot undo', () async {
    final outcome = await undoSelectionEdit(
      ticket: _ticket(),
      paster: _PlainPaster(),
    );

    expect(outcome, SelectionUndoOutcome.failed);
  });

  test('cleanInsertSerial reads the bridge and is null without it', () {
    expect(cleanInsertSerial(_UndoPaster(cleanSerial: 7)), 7);
    expect(cleanInsertSerial(_PlainPaster()), isNull);
  });
}
