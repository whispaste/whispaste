import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/selection_edit/selection_edit_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';

/// In-memory clipboard: records every write so tests can assert the
/// snapshot → sentinel → restore sequence.
class _FakeClipboard implements SelectionClipboard {
  _FakeClipboard(this.text);

  String? text;
  final writes = <String>[];
  bool throwOnRead = false;

  @override
  Future<String?> readText() async {
    if (throwOnRead) throw Exception('clipboard busy');
    return text;
  }

  @override
  Future<void> writeTransient(String value) async {
    writes.add(value);
    text = value;
  }
}

/// Simulates the target app's reaction to Cmd/Ctrl+C: with a selection it
/// replaces the clipboard, without one the clipboard stays as it was.
class _FakeCopier {
  _FakeCopier(this.clipboard, {this.selection});

  final _FakeClipboard clipboard;
  final String? selection;
  NativePasteStatus status = NativePasteStatus.success;
  bool throws = false;
  int calls = 0;

  /// When set, the target app replaces the clipboard this long after the key
  /// event — simulates a busy app that copies late.
  Duration? lateBy;

  Future<NativePasteResult> call(Duration delay) async {
    calls++;
    if (throws) throw Exception('channel gone');
    if (status == NativePasteStatus.success && selection != null) {
      final late = lateBy;
      if (late == null) {
        clipboard.text = selection;
      } else {
        unawaited(
          Future<void>.delayed(late).then((_) => clipboard.text = selection),
        );
      }
    }
    return NativePasteResult(status: status);
  }
}

class _FakeEngine implements SmartModeEngine {
  String result = 'EDITED';
  Object? error;
  Duration? delay;
  String? lastSystemPrompt;
  String? lastUserText;
  int calls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    calls++;
    lastSystemPrompt = systemPrompt;
    lastUserText = userText;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return result;
  }
}

class _FakePaster implements Paster {
  final pasted = <String>[];
  PasteOutcome outcome = PasteOutcome.success;

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    pasted.add(text);
    return outcome;
  }

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.failed;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}

const _options = PasteOptions(autoPasteDelayMs: 0, blocklist: '');

void main() {
  late _FakeClipboard clipboard;
  late _FakeEngine engine;
  late _FakePaster paster;

  SelectionReader reader(_FakeCopier copier) => SelectionReader(
    copy: copier.call,
    clipboard: clipboard,
    pollInterval: Duration.zero,
    pollTimeout: const Duration(milliseconds: 20),
    sentinelFactory: () => '<sentinel>',
  );

  SelectionEditService service(
    _FakeCopier copier, {
    Duration engineTimeout = const Duration(seconds: 5),
  }) => SelectionEditService(
    reader: reader(copier),
    engine: engine,
    paster: paster,
    engineTimeout: engineTimeout,
  );

  setUp(() {
    clipboard = _FakeClipboard('user clipboard');
    engine = _FakeEngine();
    paster = _FakePaster();
  });

  group('SelectionReader', () {
    test('returns the copied selection and restores the clipboard', () async {
      final copier = _FakeCopier(clipboard, selection: 'selected text');
      final result = await reader(copier).read();

      expect(result, isA<SelectionReadOk>());
      expect((result as SelectionReadOk).text, 'selected text');
      expect(clipboard.text, 'user clipboard');
      expect(clipboard.writes, ['<sentinel>', 'user clipboard']);
    });

    test('unchanged clipboard means no selection — still restored', () async {
      final copier = _FakeCopier(clipboard);
      final result = await reader(copier).read();

      expect(result, isA<SelectionReadEmpty>());
      expect(clipboard.text, 'user clipboard');
    });

    test('whitespace-only selection counts as no selection', () async {
      final copier = _FakeCopier(clipboard, selection: '  \n ');
      expect(await reader(copier).read(), isA<SelectionReadEmpty>());
      expect(clipboard.text, 'user clipboard');
    });

    test(
      'native copy failure is reported and the clipboard restored',
      () async {
        final copier = _FakeCopier(clipboard, selection: 'x')
          ..status = NativePasteStatus.permissionMissing;
        final result = await reader(copier).read();

        expect(result, isA<SelectionReadFailed>());
        expect(
          (result as SelectionReadFailed).status,
          NativePasteStatus.permissionMissing,
        );
        expect(clipboard.text, 'user clipboard');
      },
    );

    test('no text snapshot (image/file) is written back as empty, so the '
        'internal sentinel never stays on the clipboard', () async {
      clipboard.text = null;
      final copier = _FakeCopier(clipboard);
      expect(await reader(copier).read(), isA<SelectionReadEmpty>());
      expect(clipboard.text, '');
    });

    test('a throwing channel still restores the clipboard', () async {
      final copier = _FakeCopier(clipboard, selection: 'x')..throws = true;
      expect(await reader(copier).read(), isA<SelectionReadFailed>());
      expect(clipboard.text, 'user clipboard');
    });

    test('a target that copies after pollTimeout but within lateCopyGrace '
        'is still read before the restore', () async {
      final copier = _FakeCopier(clipboard, selection: 'slow selection')
        ..lateBy = const Duration(milliseconds: 60);
      final slowReader = SelectionReader(
        copy: copier.call,
        clipboard: clipboard,
        pollInterval: const Duration(milliseconds: 5),
        pollTimeout: const Duration(milliseconds: 10),
        lateCopyGrace: const Duration(milliseconds: 200),
        sentinelFactory: () => '<sentinel>',
      );

      final result = await slowReader.read();

      expect(result, isA<SelectionReadOk>());
      expect((result as SelectionReadOk).text, 'slow selection');
      expect(clipboard.text, 'user clipboard');
    });
  });

  group('SelectionEditService', () {
    test('success: engine gets instruction + selection, result is pasted, '
        'clipboard restored', () async {
      final copier = _FakeCopier(clipboard, selection: 'Long paragraph.');
      final outcome = await service(
        copier,
      ).run(instruction: 'make it friendlier', pasteOptions: _options);

      expect(outcome.failure, isNull);
      expect(outcome.result, 'EDITED');
      expect(engine.lastUserText, contains('make it friendlier'));
      expect(engine.lastUserText, contains('Long paragraph.'));
      expect(paster.pasted, ['EDITED']);
      expect(clipboard.text, 'user clipboard');
    });

    test('no selection: hint, engine not called, nothing pasted', () async {
      final copier = _FakeCopier(clipboard);
      final outcome = await service(
        copier,
      ).run(instruction: 'shorter', pasteOptions: _options);

      expect(outcome.failure, SelectionEditFailure.noSelection);
      expect(engine.calls, 0);
      expect(paster.pasted, isEmpty);
      expect(clipboard.text, 'user clipboard');
    });

    test('engine error: original untouched, clipboard restored', () async {
      engine.error = StateError('boom');
      final copier = _FakeCopier(clipboard, selection: 'Original');
      final outcome = await service(
        copier,
      ).run(instruction: 'shorter', pasteOptions: _options);

      expect(outcome.failure, SelectionEditFailure.engineFailed);
      expect(paster.pasted, isEmpty);
      expect(clipboard.text, 'user clipboard');
    });

    test(
      'engine timeout: nothing pasted, abandoned generation cancelled',
      () async {
        engine.delay = const Duration(milliseconds: 200);
        final copier = _FakeCopier(clipboard, selection: 'Original');
        final outcome = await service(
          copier,
          engineTimeout: const Duration(milliseconds: 20),
        ).run(instruction: 'shorter', pasteOptions: _options);

        expect(outcome.failure, SelectionEditFailure.engineFailed);
        expect(paster.pasted, isEmpty);
        expect(clipboard.text, 'user clipboard');
        expect(engine.cancelCalls, 1);
      },
    );

    test('blank engine result is a failure, never pastes empty text', () async {
      engine.result = '   ';
      final copier = _FakeCopier(clipboard, selection: 'Original');
      final outcome = await service(
        copier,
      ).run(instruction: 'shorter', pasteOptions: _options);

      expect(outcome.failure, SelectionEditFailure.engineFailed);
      expect(paster.pasted, isEmpty);
    });

    test('copy failure maps to copyFailed, engine not called', () async {
      final copier = _FakeCopier(clipboard, selection: 'x')
        ..status = NativePasteStatus.noTarget;
      final outcome = await service(
        copier,
      ).run(instruction: 'shorter', pasteOptions: _options);

      expect(outcome.failure, SelectionEditFailure.copyFailed);
      expect(engine.calls, 0);
    });

    test('paste failure is reported', () async {
      paster.outcome = PasteOutcome.permissionMissing;
      final copier = _FakeCopier(clipboard, selection: 'Original');
      final outcome = await service(
        copier,
      ).run(instruction: 'shorter', pasteOptions: _options);

      expect(outcome.failure, SelectionEditFailure.pasteFailed);
    });

    test('result is trimmed before pasting', () async {
      engine.result = '\n  Short.  \n';
      final copier = _FakeCopier(clipboard, selection: 'Original');
      await service(copier).run(instruction: 'shorter', pasteOptions: _options);
      expect(paster.pasted, ['Short.']);
    });
  });
}
