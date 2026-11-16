import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/widgets/export_format_picker.dart';

import '../fixtures/test_helpers.dart';

late L10n l10n;

/// Test harness that opens the picker on demand and records the result.
class _PickerHarness extends StatefulWidget {
  const _PickerHarness({this.formats});

  final List<ExportFormat>? formats;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  ExportFormat? _result;
  bool _resolved = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () async {
              final result = await (widget.formats == null
                  ? showWpExportFormatPicker(context)
                  : showWpExportFormatPicker(
                      context,
                      formats: widget.formats!,
                    ));
              if (!mounted) return;
              setState(() {
                _result = result;
                _resolved = true;
              });
            },
            child: const Text('Open picker'),
          ),
          Text(
            _resolved ? 'result=${_result?.name ?? 'null'}' : 'result=pending',
          ),
        ],
      ),
    );
  }
}

Future<void> _openPicker(
  WidgetTester tester, {
  List<ExportFormat>? formats,
}) async {
  await tester.pumpWidget(
    makeTestable(_PickerHarness(formats: formats), locale: const Locale('en')),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  // Resolve the English copy once so format labels are looked up via the
  // ARB key — wording tweaks in the ARB no longer silently break this suite.
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ExportFormatPicker', () {
    testWidgets('renders the five formats with labels, extensions and icons', (
      tester,
    ) async {
      await _openPicker(tester);

      // All five labels visible
      expect(find.text(l10n.exportFormatText), findsOneWidget);
      expect(find.text(l10n.exportFormatMarkdown), findsOneWidget);
      expect(find.text(l10n.exportFormatCsv), findsOneWidget);
      expect(find.text(l10n.exportFormatJson), findsOneWidget);
      expect(find.text(l10n.exportFormatWord), findsOneWidget);

      // Extension hints
      expect(find.text('.txt'), findsOneWidget);
      expect(find.text('.md'), findsOneWidget);
      expect(find.text('.csv'), findsOneWidget);
      expect(find.text('.json'), findsOneWidget);
      expect(find.text('.docx'), findsOneWidget);

      // Each option exposes an Icon widget
      expect(find.byType(Icon), findsNWidgets(5));
    });

    testWidgets('tapping an option resolves the future with that format', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.tap(find.text(l10n.exportFormatCsv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=csv'), findsOneWidget);
    });

    testWidgets('tapping Word resolves with ExportFormat.docx', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text(l10n.exportFormatWord));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=docx'), findsOneWidget);
    });

    testWidgets('Esc key dismisses the picker with null', (tester) async {
      await _openPicker(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=null'), findsOneWidget);
    });

    testWidgets('tapping the barrier dismisses with null', (tester) async {
      await _openPicker(tester);

      // Tap the top-left corner — well outside the dialog panel.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=null'), findsOneWidget);
    });

    testWidgets('Enter selects the initially highlighted (first) option', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=txt'), findsOneWidget);
    });

    testWidgets('ArrowDown moves highlight; Enter selects the new option', (
      tester,
    ) async {
      await _openPicker(tester);

      // Down twice → Markdown → CSV
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=csv'), findsOneWidget);
    });

    testWidgets('ArrowUp moves highlight back; Enter selects the new option', (
      tester,
    ) async {
      await _openPicker(tester);

      // Down 3 (JSON), Up 1 (CSV)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=csv'), findsOneWidget);
    });

    testWidgets('ArrowDown highlight wraps within the option range', (
      tester,
    ) async {
      await _openPicker(tester);

      // Press down 4 times from index 0 (TXT) → index 4 (DOCX).
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=docx'), findsOneWidget);
    });

    testWidgets('remembers last selected format using SharedPreferences', (
      tester,
    ) async {
      // 1. Initial selection: Tap JSON
      await _openPicker(tester);
      await tester.tap(find.text(l10n.exportFormatJson));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('result=json'), findsOneWidget);

      // 2. Restart picker and hit Enter immediately
      await tester.tap(find.text('Open picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 3. Should have pre-selected JSON (index 3)
      expect(find.text('result=json'), findsOneWidget);
    });
  });

  group('ExportFormatPicker last-format persistence', () {
    const notes = [ExportFormat.txt, ExportFormat.md];
    const history = [
      ExportFormat.txt,
      ExportFormat.md,
      ExportFormat.json,
      ExportFormat.csv,
      ExportFormat.docx,
    ];

    Future<String> enterResult(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      return find
          .textContaining('result=')
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .single;
    }

    testWidgets('persists the format name, not an index', (tester) async {
      await _openPicker(tester, formats: history);
      await tester.tap(find.byKey(const ValueKey('export-format-csv')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_export_format'), 'csv');
    });

    testWidgets('migrates the legacy index once and removes the old key', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'last_export_format_index': 2});
      await _openPicker(tester, formats: history);
      expect(await enterResult(tester), 'result=json');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_export_format'), 'json');
      expect(prefs.containsKey('last_export_format_index'), isFalse);
    });

    testWidgets('an out-of-range legacy index is dropped without throwing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'last_export_format_index': 9});
      await _openPicker(tester, formats: notes);
      expect(await enterResult(tester), 'result=txt');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('last_export_format_index'), isFalse);
    });

    testWidgets('the stored name survives a reordered list', (tester) async {
      SharedPreferences.setMockInitialValues({'last_export_format': 'json'});
      await _openPicker(
        tester,
        formats: const [ExportFormat.docx, ExportFormat.json, ExportFormat.txt],
      );
      expect(await enterResult(tester), 'result=json');
    });

    testWidgets('a name the caller does not offer falls back to the first', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'last_export_format': 'docx'});
      await _openPicker(tester, formats: notes);
      expect(await enterResult(tester), 'result=txt');
    });

    testWidgets('an unknown or wrongly typed value falls back to the first', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'last_export_format': 'pdf'});
      await _openPicker(tester, formats: notes);
      expect(await enterResult(tester), 'result=txt');
    });

    testWidgets('the choice is shared across callers by name', (tester) async {
      await _openPicker(tester, formats: history);
      await tester.tap(find.byKey(const ValueKey('export-format-md')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.pumpWidget(const SizedBox());
      await _openPicker(tester, formats: notes);
      expect(await enterResult(tester), 'result=md');
    });
  });
}
