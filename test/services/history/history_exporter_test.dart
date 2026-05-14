import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/services/history/history_exporter.dart';
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

// ─── HistoryEntry builder ─────────────────────────────────────────────────

HistoryEntry _entry({
  String id = 'e1',
  String content = 'transcribed text',
  String title = 'Sample Title',
  DateTime? timestamp,
  double durationSec = 3.5,
  String language = 'en',
  String tags = '[]',
  bool pinned = false,
  String model = 'whisper-small',
  bool isLocal = true,
  double costUsd = 0.0,
}) {
  return HistoryEntry(
    id: id,
    content: content,
    title: title,
    timestamp: timestamp ?? DateTime.utc(2026, 5, 14, 12, 0, 0),
    durationSec: durationSec,
    processingDurationSec: 0.5,
    language: language,
    languageHint: '',
    tags: tags,
    pinned: pinned,
    source: 'mic',
    model: model,
    isLocal: isLocal,
    costUsd: costUsd,
    archived: false,
    titleEdited: false,
  );
}

// ─── Harness ──────────────────────────────────────────────────────────────

/// Pumps a minimal widget, exposes a [BuildContext] to the test body via
/// [body], and waits for the body's future to complete.
Future<void> _withContext(
  WidgetTester tester,
  Future<void> Function(BuildContext context) body,
) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (ctx) {
          capturedContext = ctx;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await body(capturedContext);
}

HistoryExporter _exporter({
  required _FakePicker picker,
  required _FakeExporter export,
  required _FakeToaster toaster,
  Directory? downloads,
  Directory? documents,
}) {
  return HistoryExporter(
    pickerFn: picker.call,
    exporter: export.call,
    downloadsDirFn: () async => downloads,
    documentsDirFn: () async => documents,
    toaster: toaster.call,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // AC1: empty list → no picker, no toast, no export.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('empty entries: no picker, no export, no toast', (tester) async {
    final picker = _FakePicker(ExportFormat.txt);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(picker: picker, export: export, toaster: toaster);

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, const []);
    });

    expect(picker.callCount, 0);
    expect(export.calls, isEmpty);
    expect(toaster.calls, isEmpty);
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC2: picker dismissed (null) → no export, no toast.
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
      await sut.exportEntries(ctx, [_entry()]);
    });

    expect(picker.callCount, 1);
    expect(export.calls, isEmpty);
    expect(toaster.calls, isEmpty);
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC3: txt picked → export invoked with len 1, format txt, .txt path;
  //                   success toast with full path.
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
      await sut.exportEntries(ctx, [_entry(title: 'Hello')]);
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
  // AC4: tags JSON '["a","b"]' → ['a','b'] on ExportEntry.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('tags JSON decodes to list of strings', (tester) async {
    final picker = _FakePicker(ExportFormat.json);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, [_entry(tags: '["a","b"]')]);
    });

    expect(export.calls.single.entries.single.tags, ['a', 'b']);
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC5: empty tag string → [].
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('empty tag string maps to empty list', (tester) async {
    final picker = _FakePicker(ExportFormat.json);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, [_entry(tags: '')]);
    });

    expect(export.calls.single.entries.single.tags, isEmpty);
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC6: malformed tag JSON → [] (no crash, no error toast).
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('malformed tag JSON maps to empty list', (tester) async {
    final picker = _FakePicker(ExportFormat.json);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, [_entry(tags: 'not-json')]);
    });

    expect(export.calls.single.entries.single.tags, isEmpty);
    expect(
      toaster.calls.single.type,
      WpToastType.success,
      reason: 'malformed tags must not propagate as an export error',
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC7: ExportEntry.projectName is always ''.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('projectName is always empty', (tester) async {
    final picker = _FakePicker(ExportFormat.json);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, [_entry()]);
    });

    expect(export.calls.single.entries.single.projectName, '');
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC8: exporter throws → error toast with exception message,
  //                        no success toast.
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
      await sut.exportEntries(ctx, [_entry()]);
    });

    expect(toaster.calls, hasLength(1));
    expect(toaster.calls.single.type, WpToastType.error);
    expect(toaster.calls.single.message, 'disk full');
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC9: multi-entry → defaultFilename + all entries passed.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('multi-entry export uses defaultFilename', (tester) async {
    final picker = _FakePicker(ExportFormat.csv);
    final export = _FakeExporter();
    final toaster = _FakeToaster();
    final sut = _exporter(
      picker: picker,
      export: export,
      toaster: toaster,
      downloads: Directory('/tmp'),
    );

    await _withContext(tester, (ctx) async {
      await sut.exportEntries(ctx, [
        _entry(id: 'a'),
        _entry(id: 'b'),
        _entry(id: 'c'),
      ]);
    });

    final call = export.calls.single;
    expect(call.entries, hasLength(3));
    // defaultFilename collapses multi-entry to 'whispaste-export.<ext>'.
    expect(call.path, endsWith('/whispaste-export.csv'));
  });

  // ───────────────────────────────────────────────────────────────────────
  // AC10: Downloads first; falls back to Documents when Downloads is null.
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
      await sut.exportEntries(ctx, [_entry()]);
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
      await sut.exportEntries(ctx, [_entry()]);
    });

    expect(export.calls.single.path, startsWith('/documents/'));
  });
}
