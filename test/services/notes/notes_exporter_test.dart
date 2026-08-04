/// Tests for [NotesExporter] — Vorbild `history_exporter_test.dart`, adapted
/// for a single [Note] + its tags instead of a list of [HistoryEntry].
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/services/notes/notes_exporter.dart';
import 'package:whispaste/widgets/toast.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────

/// Records each picker invocation and answers with the queued result.
class _FakePicker {
  _FakePicker(this._result);
  final ExportFormat? _result;
  int callCount = 0;

  Future<ExportFormat?> call(BuildContext context) async {
    callCount++;
    return _result;
  }
}

class _ExporterCall {
  _ExporterCall(this.entries, this.format, this.path);
  final List<ExportEntry> entries;
  final ExportFormat format;
  final String path;
}

/// Captures arguments and either returns a byte count or throws.
class _FakeExporter {
  _FakeExporter({this.throwError});
  final Object? throwError;
  final List<_ExporterCall> calls = [];

  Future<int> call(
    List<ExportEntry> entries,
    ExportFormat format,
    String path,
  ) async {
    calls.add(_ExporterCall(entries, format, path));
    if (throwError != null) throw throwError!;
    return 42;
  }
}

class _ToasterCall {
  _ToasterCall(this.type, this.message);
  final WpToastType type;
  final String message;
}

/// Captures toast calls.
class _FakeToaster {
  final List<_ToasterCall> calls = [];

  void call(BuildContext context, WpToastType type, String message) {
    calls.add(_ToasterCall(type, message));
  }
}

// ─── Note / Tag builders ──────────────────────────────────────────────────

Note _note({
  String id = 'n1',
  String content = 'Grocery list\nMilk, eggs, bread',
  bool pinned = false,
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime.utc(2026, 5, 14, 12, 0, 0);
  return Note(
    id: id,
    content: content,
    pinned: pinned,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime.utc(2026, 5, 14));

// ─── Harness ──────────────────────────────────────────────────────────────

/// Pumps a minimal widget, exposes a [BuildContext] to the test body via
/// [body], and waits for the body's future to complete.
Future<void> _withContext(
  WidgetTester tester,
  Future<void> Function(BuildContext context) body,
) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    Localizations(
      locale: const Locale('en'),
      delegates: L10n.localizationsDelegates,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await body(capturedContext);
}

NotesExporter _exporter({
  required _FakePicker picker,
  required _FakeExporter export,
  required _FakeToaster toaster,
  Directory? downloads,
  Directory? documents,
}) {
  return NotesExporter(
    pickerFn: picker.call,
    exporter: export.call,
    downloadsDirFn: () async => downloads,
    documentsDirFn: () async => documents,
    toaster: toaster.call,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // Picker dismissed (null) → no export, no toast.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('picker returns null: no export and no toast', (tester) async {
    final picker = _FakePicker(null);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory.systemTemp,
    );

    await _withContext(tester, (ctx) async {
      await sut.exportNote(ctx, _note(), const []);
    });

    expect(picker.callCount, 1);
    expect(export.calls, isEmpty);
    expect(toaster.calls, isEmpty);
  });

  // ───────────────────────────────────────────────────────────────────────
  // txt picked → export invoked with 1 entry, format txt, .txt path;
  // success toast with full path.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('txt format: export invoked + success toast', (tester) async {
    final picker = _FakePicker(ExportFormat.txt);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final dir = Directory('/fake/downloads');
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: dir,
    );

    await _withContext(tester, (ctx) async {
      await sut.exportNote(ctx, _note(content: 'Hello\nWorld'), const []);
    });

    expect(export.calls, hasLength(1));
    final call = export.calls.single;
    expect(call.entries, hasLength(1));
    expect(call.format, ExportFormat.txt);
    expect(call.path, endsWith('.txt'));
    expect(call.path, startsWith('/fake/downloads/'));

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.success);
    expect(toaster.calls.single.message, 'Exported to ${call.path}');
  });

  // ───────────────────────────────────────────────────────────────────────
  // Note → ExportEntry mapping.
  // ───────────────────────────────────────────────────────────────────────

  group('Note → ExportEntry mapping', () {
    testWidgets('title derives from the first non-blank content line', (
      tester,
    ) async {
      final picker = _FakePicker(ExportFormat.md);
      final export = _FakeExporter();
      final toaster = _FakeToaster();
      final sut = _exporter(
        picker: picker,
        export: export,
        toaster: toaster,
        downloads: Directory('/tmp'),
      );

      await _withContext(tester, (ctx) async {
        await sut.exportNote(
          ctx,
          _note(content: 'Grocery list\nMilk, eggs'),
          const [],
        );
      });

      final entry = export.calls.single.entries.single;
      expect(entry.title, 'Grocery list');
      expect(entry.text, 'Grocery list\nMilk, eggs');
    });

    testWidgets('blank content falls back to the localized "Untitled"', (
      tester,
    ) async {
      final picker = _FakePicker(ExportFormat.md);
      final export = _FakeExporter();
      final toaster = _FakeToaster();
      final sut = _exporter(
        picker: picker,
        export: export,
        toaster: toaster,
        downloads: Directory('/tmp'),
      );

      await _withContext(tester, (ctx) async {
        await sut.exportNote(ctx, _note(content: '   '), const []);
        expect(
          export.calls.single.entries.single.title,
          L10n.of(ctx).notesUntitled,
        );
      });
    });

    testWidgets('tags map to their names, pinned flag is carried through', (
      tester,
    ) async {
      final picker = _FakePicker(ExportFormat.md);
      final export = _FakeExporter();
      final toaster = _FakeToaster();
      final sut = _exporter(
        picker: picker,
        export: export,
        toaster: toaster,
        downloads: Directory('/tmp'),
      );

      await _withContext(tester, (ctx) async {
        await sut.exportNote(ctx, _note(pinned: true), [
          _tag('t1', 'work'),
          _tag('t2', 'errands'),
        ]);
      });

      final entry = export.calls.single.entries.single;
      expect(entry.tags, ['work', 'errands']);
      expect(entry.pinned, isTrue);
    });

    testWidgets('timestamp uses updatedAt, ISO-8601 encoded', (tester) async {
      final picker = _FakePicker(ExportFormat.md);
      final export = _FakeExporter();
      final toaster = _FakeToaster();
      final sut = _exporter(
        picker: picker,
        export: export,
        toaster: toaster,
        downloads: Directory('/tmp'),
      );
      final updatedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

      await _withContext(tester, (ctx) async {
        await sut.exportNote(ctx, _note(updatedAt: updatedAt), const []);
      });

      expect(
        export.calls.single.entries.single.timestamp,
        updatedAt.toIso8601String(),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Exporter throws → error toast with exception message, no success toast.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('exporter throws: error toast, no success toast', (tester) async {
    final picker = _FakePicker(ExportFormat.txt);
    final export = _FakeExporter(throwError: Exception('disk full'));
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportNote(ctx, _note(), const []);
    });

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.error);
    expect(toaster.calls.single.message, 'disk full');
  });

  // ───────────────────────────────────────────────────────────────────────
  // Downloads first; falls back to Documents when Downloads is null.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('uses Downloads directory when available', (tester) async {
    final picker = _FakePicker(ExportFormat.txt);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/downloads'),
      documents: Directory('/documents'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportNote(ctx, _note(), const []);
    });

    expect(export.calls.single.path, startsWith('/downloads/'));
  });

  testWidgets('falls back to Documents when Downloads is null', (tester) async {
    final picker = _FakePicker(ExportFormat.txt);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: null,
      documents: Directory('/documents'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportNote(ctx, _note(), const []);
    });

    expect(export.calls.single.path, startsWith('/documents/'));
  });
}
