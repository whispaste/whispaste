import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/snippet_picker_trigger_row.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SnippetPickerTriggerRow (UX-030)', () {
    testWidgets('lives in Settings under its own row id', (tester) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      expect(
        find.byKey(settingsRowKey('general-snippet-picker-trigger')),
        findsOneWidget,
      );
    });

    testWidgets('commits the typed word only after the user pauses', (
      tester,
    ) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      await tester.enterText(find.byType(TextField), 'snippet');
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.stored, '');

      await tester.pump(const Duration(milliseconds: 400));
      expect(store.stored, 'snippet');
    });

    testWidgets('a pending word is written when the user leaves the page', (
      tester,
    ) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      await tester.enterText(find.byType(TextField), 'snippet');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(store.stored, 'snippet');
    });

    testWidgets('a pending word is written when the app is paused', (
      tester,
    ) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      await tester.enterText(find.byType(TextField), 'snippet');
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(store.stored, 'snippet');
    });

    testWidgets(
      'an external change replaces the text and drops pending typing',
      (tester) async {
        final store = _FakeStore();
        await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

        await tester.enterText(find.byType(TextField), 'typed');
        await tester.pump(const Duration(milliseconds: 100));
        await _pump(
          tester,
          store,
          const SnippetPickerTriggerRow(trigger: 'imported'),
        );

        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'imported',
        );
        await tester.pump(const Duration(seconds: 1));
        expect(store.stored, '');
      },
    );

    testWidgets('limits the word to 64 characters', (tester) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      await tester.enterText(find.byType(TextField), 'x' * 80);
      await tester.pump(const Duration(seconds: 1));

      expect(store.stored, 'x' * 64);
    });

    testWidgets('strips control characters from the word', (tester) async {
      final store = _FakeStore();
      await _pump(tester, store, const SnippetPickerTriggerRow(trigger: ''));

      await tester.enterText(find.byType(TextField), 'sni\u0007ppet');
      await tester.pump(const Duration(seconds: 1));

      expect(store.stored, 'snippet');
    });
  });
}

/// Pumps the row inside an 800 px window with the given text scale, backed by
/// [store]. Pumping again with the same store simulates a rebuild from outside.
Future<void> _pump(
  WidgetTester tester,
  _FakeStore store,
  Widget row, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    makeTestable(
      _Window(textScale: textScale, child: row),
      size: const Size(800, 716),
      locale: locale,
      overrides: [settingsProvider.overrideWith(store.create)],
    ),
  );
  await tester.pumpAndSettle();
}

/// Applies the text scale and constrains the row to the 800 px window.
class _Window extends StatelessWidget {
  const _Window({required this.textScale, required this.child});

  final double textScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: SizedBox(width: 800, child: child),
    );
  }
}

/// Holds the notifier the row commits to, so a test can read what was written.
class _FakeStore {
  _FakeSettingsNotifier? _notifier;

  _FakeSettingsNotifier create() =>
      _notifier = _FakeSettingsNotifier(const AppSettings());

  String get stored => _notifier!.current.behavior.snippetPickerTrigger;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    // Only the held value: `state` is unreachable once the scope is gone.
    _settings = updater(_settings);
  }
}
