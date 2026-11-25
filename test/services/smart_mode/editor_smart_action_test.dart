import 'dart:async' show Completer;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/smart_actions/editor_smart_action_flow.dart';
import 'package:whispaste/services/drift_recording_store.dart'
    show factKnownTermsProvider;
import 'package:whispaste/services/selection_edit/selection_edit_prompt.dart'
    show selectionEditInstructionSystemPrompt;
import 'package:whispaste/services/smart_mode/editor_smart_action.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_retroactive_service.dart'
    show SmartModeRetroactiveFailureReason;
import 'package:whispaste/services/user_models/user_model_use.dart'
    show smartModeLocalModelReadyProvider;

class _FakeEngine implements SmartModeEngine {
  String? result;
  bool hang = false;
  Object? error;
  int runCalls = 0;
  int cancelCalls = 0;
  String? lastSystemPrompt;
  String? lastUserText;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    runCalls++;
    lastSystemPrompt = systemPrompt;
    lastUserText = userText;
    if (hang) await Completer<void>().future;
    final e = error;
    if (e != null) throw e;
    return result ?? userText;
  }

  @override
  Future<void> cancel() async => cancelCalls++;
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

TextEditingValue _caret(String text, int offset) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset),
);

void main() {
  group('editorSmartActionRange', () {
    test('selection, caret paragraph, blank and invalid cases', () {
      const text = 'First line.\n\n  Second paragraph here.  \nThird.';
      final cases = <(String, TextEditingValue, String?)>[
        (
          'a selection is taken as is, without outer white space',
          const TextEditingValue(
            text: text,
            selection: TextSelection(baseOffset: 13, extentOffset: 40),
          ),
          'Second paragraph here.',
        ),
        (
          'caret in the middle of a line',
          _caret(text, 20),
          'Second paragraph here.',
        ),
        ('caret at the start of the text', _caret(text, 0), 'First line.'),
        ('caret at the end of the text', _caret(text, text.length), 'Third.'),
        ('caret at the end of a line', _caret(text, 11), 'First line.'),
        ('caret on a blank line', _caret(text, 12), null),
        (
          'a blank selection',
          const TextEditingValue(
            text: 'a   b',
            selection: TextSelection(baseOffset: 1, extentOffset: 4),
          ),
          null,
        ),
        ('no caret', const TextEditingValue(text: text), null),
      ];
      for (final (name, value, expected) in cases) {
        final range = editorSmartActionRange(value);
        expect(range?.textInside(value.text), expected, reason: name);
      }
    });

    test('caret paragraph never spans the whole multi-line text', () {
      const text = 'One.\nTwo.\nThree.';
      final range = editorSmartActionRange(_caret(text, 6))!;
      expect(range.textInside(text), 'Two.');
    });
  });

  group('applyEditorSmartActionResult', () {
    test('replaces only the range and selects the result', () {
      const value = TextEditingValue(text: 'Keep. Change me. Keep.');
      const range = TextRange(start: 6, end: 16);
      final out = applyEditorSmartActionResult(value, range, 'Changed.')!;
      expect(out.text, 'Keep. Changed. Keep.');
      expect(out.selection.textInside(out.text), 'Changed.');
    });

    test('a range outside the current text replaces nothing', () {
      const value = TextEditingValue(text: 'short');
      expect(
        applyEditorSmartActionResult(
          value,
          const TextRange(start: 2, end: 40),
          'x',
        ),
        isNull,
      );
      expect(applyEditorSmartActionResult(value, TextRange.empty, 'x'), isNull);
    });
  });

  test('custom instruction keeps instruction and text apart', () {
    final out = editorSmartActionInstructionText('  Make it formal ', 'hi');
    expect(out, 'Instruction: Make it formal\n\n<text>\nhi\n</text>');
  });

  group('EditorSmartActionService.run', () {
    late _FakeEngine engine;
    late ProviderContainer container;

    ProviderContainer build({
      SmartModeProviderType provider = SmartModeProviderType.local,
      bool modelReady = true,
    }) => ProviderContainer(
      overrides: [
        factKnownTermsProvider.overrideWith(
          (ref) =>
              () async => const <String>[],
        ),
        settingsProvider.overrideWith(
          () => _FakeSettings(
            AppSettings.defaults.copyWithSections(
              smartMode: AppSettings.defaults.smartMode.copyWith(
                provider: provider.value,
              ),
            ),
          ),
        ),
        smartModeLocalModelReadyProvider.overrideWithValue(modelReady),
        smartModeEngineProvider.overrideWith((ref) => engine),
      ],
    );

    Future<EditorSmartActionResult> run(
      EditorSmartAction action,
      String text, {
      String? instruction,
    }) async {
      await container.read(settingsProvider.future);
      return container
          .read(editorSmartActionServiceProvider)
          .run(action: action, text: text, instruction: instruction);
    }

    SmartModeRetroactiveFailureReason? reasonOf(EditorSmartActionResult r) =>
        r is EditorSmartActionFailure ? r.reason : null;

    setUp(() {
      engine = _FakeEngine();
      EditorSmartActionService.timeoutOverride = const Duration(
        milliseconds: 200,
      );
    });

    tearDown(() {
      EditorSmartActionService.timeoutOverride = null;
      container.dispose();
    });

    test('local path without a model fails before the engine', () async {
      container = build(modelReady: false);
      final r = await run(EditorSmartAction.cleanUp, 'some text');
      expect(reasonOf(r), SmartModeRetroactiveFailureReason.modelMissing);
      expect(engine.runCalls, 0);
    });

    test('the chosen cloud provider runs without a local model', () async {
      container = build(
        provider: SmartModeProviderType.openAI,
        modelReady: false,
      );
      engine.result = 'Some text.';
      final r = await run(EditorSmartAction.cleanUp, 'some text');
      expect((r as EditorSmartActionSuccess).text, 'Some text.');
      expect(engine.runCalls, 1);
    });

    test('success trims; custom sends the delimited instruction', () async {
      container = build();
      engine.result = '  Dear team, the meeting is at 10.  ';
      final r = await run(
        EditorSmartAction.custom,
        'hey team meeting at 10',
        instruction: 'formal',
      );
      expect(
        (r as EditorSmartActionSuccess).text,
        'Dear team, the meeting is at 10.',
      );
      expect(engine.lastSystemPrompt, selectionEditInstructionSystemPrompt);
      expect(
        engine.lastUserText,
        editorSmartActionInstructionText('formal', 'hey team meeting at 10'),
      );
    });

    test(
      'blank result, changed facts, error and timeout replace nothing',
      () async {
        container = build();
        engine.result = '   ';
        expect(
          reasonOf(await run(EditorSmartAction.shorten, 'Pay 40 euros.')),
          SmartModeRetroactiveFailureReason.blankResult,
        );
        engine.result = 'Pay 50 euros.';
        expect(
          reasonOf(await run(EditorSmartAction.shorten, 'Pay 40 euros.')),
          SmartModeRetroactiveFailureReason.factsChanged,
        );
        engine
          ..result = null
          ..error = StateError('engine down');
        expect(
          reasonOf(await run(EditorSmartAction.cleanUp, 'text')),
          SmartModeRetroactiveFailureReason.engineError,
        );
        engine
          ..error = null
          ..hang = true;
        expect(
          reasonOf(await run(EditorSmartAction.cleanUp, 'text')),
          SmartModeRetroactiveFailureReason.timeout,
        );
        expect(engine.cancelCalls, 1);
      },
    );
  });
}
