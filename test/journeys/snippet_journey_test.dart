/// Journey: Snippet anlegen → per Picker einfügen → bearbeiten → löschen.
///
/// Real providers, real [SnippetsPage], real picker service and real
/// dispatch ([openSnippetPicker], the same entrypoint the systemwide hotkey and
/// the spoken trigger both reach), real in-memory Drift DB. Faked: only the OS
/// seams — the native picker panel ([_FakePanel]) and the paste bridge
/// ([_FakePaster]). The hotkey itself is not pressed; its contract starts at
/// [openSnippetPicker], which is what `openSnippetPickerViaHotkey` calls.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_dispatch.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_events.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

/// Native picker panel stand-in: records what it was asked to show and lets
/// the test play the user's pick or dismissal.
class _FakePanel implements SnippetPickerController {
  final shown = <List<Map<String, String>>>[];
  final _events = StreamController<SnippetPickerEvent>.broadcast();

  void pick(String id) => _events.add(SnippetPickerItemSelected(id));

  @override
  Future<void> show({required List<Map<String, String>> items}) async {
    shown.add(items);
  }

  @override
  Future<void> hide() async {}

  @override
  Stream<SnippetPickerEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

/// Clipboard/paste bridge stand-in: records every body that would have been
/// written into the target window.
class _FakePaster implements Paster {
  final pasted = <String>[];
  PasteOutcome nextOutcome = PasteOutcome.success;

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    pasted.add(text);
    return nextOutcome;
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async {
    throw UnimplementedError('typeText is not used for a static snippet');
  }

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

/// The hotkey entrypoint as a provider, so the test gets a real [Ref] and
/// runs the production [openSnippetPicker] unchanged.
final _openPickerProvider =
    Provider<Future<SnippetPickerShowResult> Function()>(
      (ref) =>
          () => openSnippetPicker(ref, 'journey'),
    );

late L10n l10n;

Widget _subject({required _FakePanel? panel, required _FakePaster paster}) {
  return makeTestable(
    const SnippetsPage(),
    locale: const Locale('en'),
    overrides: [
      settingsProvider.overrideWith(_FakeSettingsNotifier.new),
      snippetPickerAvailabilityProvider.overrideWithValue(true),
      snippetPickerControllerProvider.overrideWithValue(panel),
      pasterProvider.overrideWithValue(paster),
    ],
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SnippetsPage)));

/// Ctrl (Cmd on macOS) + N — the page's "new snippet" chord.
Future<void> _pressNewItemChord(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Finder _fieldIn(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

Future<void> _fillDialog(
  WidgetTester tester, {
  required String title,
  required String body,
}) async {
  await tester.enterText(_fieldIn('snippets-title-field'), title);
  await tester.enterText(_fieldIn('snippets-body-field'), body);
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<WpButton>(find.byKey(const ValueKey('snippets-save')))
        .onPressed !=
    null;

Future<void> _createSnippet(
  WidgetTester tester, {
  required String title,
  required String body,
}) async {
  await _pressNewItemChord(tester);
  await _fillDialog(tester, title: title, body: body);
  await tester.tap(find.byKey(const ValueKey('snippets-save')));
  await tester.pumpAndSettle();
}

/// Runs the hotkey entrypoint and returns its outcome.
Future<SnippetPickerShowResult> _openPicker(WidgetTester tester) async {
  final open = _container(tester).read(_openPickerProvider);
  final result = await open();
  await tester.pumpAndSettle();
  return result;
}

/// Plays a pick in the native panel and lets the service handle it.
Future<void> _pickInPanel(
  WidgetTester tester,
  _FakePanel panel,
  String id,
) async {
  panel.pick(id);
  await tester.pumpAndSettle();
}

String _onlySnippetId(WidgetTester tester) =>
    _container(tester).read(snippetsProvider).value!.single.id;

int _insertCount(WidgetTester tester) =>
    _container(tester).read(telemetrySessionAggregatorProvider).debugCounts[(
      'snippets',
      'insert',
      null,
    )] ??
    0;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Snippet journey', () {
    testWidgets(
      'create, insert via picker, edit, insert again, delete, and the picker '
      'no longer offers it',
      (tester) async {
        final panel = _FakePanel();
        final paster = _FakePaster();
        await tester.pumpWidget(_subject(panel: panel, paster: paster));
        await tester.pumpAndSettle();

        // 1. Anlegen.
        await _createSnippet(tester, title: 'Signature', body: 'Best,\nSilvio');
        final id = _onlySnippetId(tester);
        expect(
          find.byKey(ValueKey('snippets-row-$id')),
          findsOneWidget,
          reason: 'the new snippet appears as a row',
        );

        // 2. Einfügen über den Picker-Pfad: Hotkey-Entrypoint öffnet das
        //    Panel mit genau diesem Snippet.
        expect(await _openPicker(tester), SnippetPickerShowResult.shown);
        expect(panel.shown, hasLength(1));
        expect(panel.shown.single.single, {
          'id': id,
          'title': 'Signature',
          'body': 'Best,\nSilvio',
        });

        await _pickInPanel(tester, panel, id);
        expect(paster.pasted, ['Best,\nSilvio']);
        expect(_insertCount(tester), 1);

        // 3. Bearbeiten: der geänderte Inhalt ist beim nächsten Einfügen da.
        await tester.tap(find.byKey(ValueKey('snippets-row-$id')));
        await tester.pumpAndSettle();
        await _fillDialog(
          tester,
          title: 'Signature',
          body: 'Kind regards,\nSilvio',
        );
        await tester.tap(find.byKey(const ValueKey('snippets-save')));
        await tester.pumpAndSettle();
        expect(_onlySnippetId(tester), id, reason: 'edit keeps the same row');

        expect(await _openPicker(tester), SnippetPickerShowResult.shown);
        expect(panel.shown.last.single['body'], 'Kind regards,\nSilvio');
        await _pickInPanel(tester, panel, id);
        expect(paster.pasted, ['Best,\nSilvio', 'Kind regards,\nSilvio']);
        expect(_insertCount(tester), 2);

        // 4. Löschen: Hover zeigt die Zeilenaktion, Bestätigung entfernt es.
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(
          tester.getCenter(find.byKey(ValueKey('snippets-row-$id'))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('snippets-delete-$id')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.snippetsDeleteTitle), findsOneWidget);
        await tester.tap(find.byType(WpButton).last);
        await tester.pumpAndSettle();

        expect(_container(tester).read(snippetsProvider).value, isEmpty);
        expect(find.byKey(ValueKey('snippets-row-$id')), findsNothing);

        // 5. Der Picker bietet es nicht mehr an — er bleibt zu und meldet das.
        expect(await _openPicker(tester), SnippetPickerShowResult.emptyList);
        expect(
          panel.shown,
          hasLength(2),
          reason: 'no third panel was opened for an empty list',
        );
        expect(
          _container(tester).read(recordingInfoProvider),
          'info_snippet_picker_empty',
        );
        expect(paster.pasted, hasLength(2), reason: 'nothing new was pasted');
      },
    );

    testWidgets('a blank title or a blank body keeps save disabled and stores '
        'nothing', (tester) async {
      await tester.pumpWidget(
        _subject(panel: _FakePanel(), paster: _FakePaster()),
      );
      await tester.pumpAndSettle();

      await _pressNewItemChord(tester);

      await _fillDialog(tester, title: 'Signature', body: '');
      expect(_saveEnabled(tester), isFalse, reason: 'empty body');

      await _fillDialog(tester, title: '   ', body: 'Best, Silvio');
      expect(_saveEnabled(tester), isFalse, reason: 'whitespace-only title');

      await _fillDialog(tester, title: 'Signature', body: '  \n  ');
      expect(_saveEnabled(tester), isFalse, reason: 'whitespace-only body');

      await _fillDialog(tester, title: '', body: '');
      expect(_saveEnabled(tester), isFalse, reason: 'both empty');

      await tester.tap(find.byKey(const ValueKey('snippets-save')));
      await tester.pumpAndSettle();

      expect(_container(tester).read(snippetsProvider).value, isEmpty);
      expect(
        find.byKey(const ValueKey('snippets-save')),
        findsOneWidget,
        reason: 'the dialog stays open, the rejected save did nothing',
      );
    });

    testWidgets('with no snippets the picker stays closed and says why', (
      tester,
    ) async {
      final panel = _FakePanel();
      await tester.pumpWidget(_subject(panel: panel, paster: _FakePaster()));
      await tester.pumpAndSettle();

      expect(await _openPicker(tester), SnippetPickerShowResult.emptyList);
      expect(panel.shown, isEmpty);
      expect(
        _container(tester).read(recordingInfoProvider),
        'info_snippet_picker_empty',
      );
    });

    testWidgets('on a platform without a native panel nothing is opened and '
        'nothing is pasted', (tester) async {
      final paster = _FakePaster();
      await tester.pumpWidget(_subject(panel: null, paster: paster));
      await tester.pumpAndSettle();

      await _createSnippet(tester, title: 'Signature', body: 'Best');

      expect(await _openPicker(tester), SnippetPickerShowResult.unavailable);
      expect(paster.pasted, isEmpty);
      expect(_container(tester).read(recordingInfoProvider), isNull);
    });

    testWidgets('a pick the service does not know about pastes nothing', (
      tester,
    ) async {
      final panel = _FakePanel();
      final paster = _FakePaster();
      await tester.pumpWidget(_subject(panel: panel, paster: paster));
      await tester.pumpAndSettle();

      await _createSnippet(tester, title: 'Signature', body: 'Best');
      expect(await _openPicker(tester), SnippetPickerShowResult.shown);

      await _pickInPanel(tester, panel, 'not-a-shown-id');

      expect(paster.pasted, isEmpty);
      expect(_insertCount(tester), 0);
    });

    testWidgets('a paste the OS refuses is not counted as an insert', (
      tester,
    ) async {
      final panel = _FakePanel();
      final paster = _FakePaster()..nextOutcome = PasteOutcome.blocked;
      await tester.pumpWidget(_subject(panel: panel, paster: paster));
      await tester.pumpAndSettle();

      await _createSnippet(tester, title: 'Signature', body: 'Best');
      expect(await _openPicker(tester), SnippetPickerShowResult.shown);
      await _pickInPanel(tester, panel, _onlySnippetId(tester));

      expect(paster.pasted, ['Best'], reason: 'the paste was attempted');
      expect(_insertCount(tester), 0);
    });
  });
}
