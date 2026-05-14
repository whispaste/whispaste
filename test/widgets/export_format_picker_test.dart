import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/widgets/export_format_picker.dart';

import '../fixtures/test_helpers.dart';

/// Test harness that opens the picker on demand and records the result.
class _PickerHarness extends StatefulWidget {
  const _PickerHarness();

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
              final result = await showExportFormatPicker(context);
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

Future<void> _openPicker(WidgetTester tester) async {
  await tester.pumpWidget(makeTestable(const _PickerHarness()));
  await tester.tap(find.text('Open picker'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('ExportFormatPicker', () {
    testWidgets('renders five options in stable TXT → MD → CSV → JSON → DOCX '
        'order with labels and icons', (tester) async {
      await _openPicker(tester);

      // All five labels visible
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('Word'), findsOneWidget);

      // Extension hints
      expect(find.text('.txt'), findsOneWidget);
      expect(find.text('.md'), findsOneWidget);
      expect(find.text('.csv'), findsOneWidget);
      expect(find.text('.json'), findsOneWidget);
      expect(find.text('.docx'), findsOneWidget);

      // Each option exposes an Icon widget
      expect(find.byType(Icon), findsNWidgets(5));

      // Order is preserved top-to-bottom
      final txtY = tester.getCenter(find.text('Text')).dy;
      final mdY = tester.getCenter(find.text('Markdown')).dy;
      final csvY = tester.getCenter(find.text('CSV')).dy;
      final jsonY = tester.getCenter(find.text('JSON')).dy;
      final docxY = tester.getCenter(find.text('Word')).dy;
      expect(txtY < mdY, isTrue, reason: 'TXT before MD');
      expect(mdY < csvY, isTrue, reason: 'MD before CSV');
      expect(csvY < jsonY, isTrue, reason: 'CSV before JSON');
      expect(jsonY < docxY, isTrue, reason: 'JSON before DOCX');
    });

    testWidgets('tapping an option resolves the future with that format', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.tap(find.text('CSV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('result=csv'), findsOneWidget);
    });

    testWidgets('tapping Word resolves with ExportFormat.docx', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text('Word'));
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
  });
}
