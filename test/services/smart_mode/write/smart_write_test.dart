import 'dart:async';
import 'dart:ui' show Locale;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_preview.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_environment.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_notice.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_prompt.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_service.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

class _FakeEngine implements SmartModeEngine {
  String result = 'DRAFT';
  Object? error;
  Completer<void>? hold;
  int cancelCalls = 0;
  String? lastUserText;

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (hold?.isCompleted == false) hold!.complete();
  }

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    lastUserText = userText;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return result;
  }
}

/// A cloud engine with its own write path (#251).
class _FakeWriteEngine extends _FakeEngine implements SmartWriteEngine {
  final jobs = <String>[];
  final cancelledJobs = <String>[];
  Completer<String>? pending;
  bool ignoreCancel = false;

  @override
  Duration get writeTimeout => const Duration(seconds: 30);

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) => throw StateError('write jobs must not use run');

  @override
  Future<String> write({
    required String systemPrompt,
    required String userText,
    required String jobId,
    Map<String, Object>? jsonSchema,
  }) async {
    jobs.add(jobId);
    lastUserText = userText;
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return result;
  }

  @override
  void cancelWrite(String jobId) {
    cancelledJobs.add(jobId);
    if (!ignoreCancel && pending?.isCompleted == false) {
      pending!.completeError(
        const SmartWriteEngineException(smartWriteCancelledCode),
      );
    }
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

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  group('buildSmartWritePrompt', () {
    test('the profile only enters when filled in and switched on', () {
      final on = buildSmartWritePrompt(
        instruction: 'decline politely',
        profile: 'Anna, sign off with Best',
        useProfile: true,
      );
      expect(on.userText, contains('<profile>'));
      expect(on.userText, contains('Anna'));

      final off = buildSmartWritePrompt(
        instruction: 'decline politely',
        profile: 'Anna',
      );
      expect(off.userText, isNot(contains('Anna')));

      final blank = buildSmartWritePrompt(
        instruction: 'decline politely',
        profile: '   ',
        useProfile: true,
      );
      expect(blank.userText, isNot(contains('<profile>')));
      expect(blank.systemPrompt, smartWriteSystemPrompt);
    });

    test('clipboard reaches the cloud only after confirmation (D20)', () {
      SmartWritePrompt build({bool cloud = false, bool confirmed = false}) =>
          buildSmartWritePrompt(
            instruction: 'reply',
            clipboard: 'SECRET NOTE',
            cloud: cloud,
            cloudClipboardConfirmed: confirmed,
          );
      expect(build(cloud: true).userText, isNot(contains('SECRET NOTE')));
      expect(build(cloud: true).userText, isNot(contains('<clipboard>')));
      expect(
        build(cloud: true, confirmed: true).userText,
        contains('SECRET NOTE'),
      );
      expect(build().userText, contains('<clipboard>'));
    });
  });

  group('SmartWriteService', () {
    late _FakeEngine engine;
    setUp(() => engine = _FakeEngine());

    test('returns the trimmed draft', () async {
      engine.result = '  Hello Anna  \n';
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'greet Anna');
      expect(out.text, 'Hello Anna');
      expect(out.failure, isNull);
      expect(engine.lastUserText, contains('greet Anna'));
    });

    test('engine error is a failure, never a draft', () async {
      engine.error = StateError('boom');
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'x');
      expect(out.text, isNull);
      expect(out.failure, SmartWriteFailure.engineFailed);
    });

    test('timeout cancels the engine and fails', () async {
      engine.hold = Completer<void>();
      final out = await SmartWriteService(
        engine: engine,
        timeout: const Duration(milliseconds: 20),
      ).write(instruction: 'x');
      expect(out.failure, SmartWriteFailure.timedOut);
      expect(engine.cancelCalls, 1);
    });

    test('Esc while writing stops the running generation', () async {
      engine.hold = Completer<void>();
      final service = SmartWriteService(engine: engine);
      final run = service.write(instruction: 'x');
      await service.cancel();
      await run;
      expect(engine.cancelCalls, 1);
    });

    test('cancel without a running write leaves the engine alone', () async {
      final service = SmartWriteService(engine: engine);
      await service.cancel();
      await service.write(instruction: 'x');
      await service.cancel();
      expect(engine.cancelCalls, 0);
    });

    test('blank answer fails', () async {
      engine.result = '  \n ';
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'x');
      expect(out.failure, SmartWriteFailure.emptyResponse);
    });

    test('over-long (cut off) answer fails', () async {
      engine.result = 'a' * 50;
      final out = await SmartWriteService(
        engine: engine,
        maxOutputChars: 20,
      ).write(instruction: 'x');
      expect(out.failure, SmartWriteFailure.truncated);
      expect(out.text, isNull);
    });
  });

  group('SmartWriteService with a write engine (#251)', () {
    late _FakeWriteEngine engine;
    setUp(() => engine = _FakeWriteEngine());

    test('uses write, not run, and skips the local length bound', () async {
      engine.result = 'a' * 9000;
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'x');
      expect(out.text, hasLength(9000));
      expect(engine.jobs, hasLength(1));
    });

    test(
      'engine codes become their failure, unknown ones engineFailed',
      () async {
        engine.error = const SmartWriteEngineException(
          'smart_write_openai_rate_limited',
        );
        final service = SmartWriteService(engine: engine);
        expect(
          (await service.write(instruction: 'x')).failure,
          SmartWriteFailure.openAiRateLimited,
        );
        engine.error = const SmartWriteEngineException('smart_write_new_thing');
        expect(
          (await service.write(instruction: 'x')).failure,
          SmartWriteFailure.engineFailed,
        );
      },
    );

    test('Esc aborts exactly the running job', () async {
      engine.pending = Completer<String>();
      final service = SmartWriteService(engine: engine);
      final run = service.write(instruction: 'x');
      await Future<void>.delayed(Duration.zero);
      await service.cancel();
      final out = await run;
      expect(engine.cancelledJobs, engine.jobs);
      expect(engine.cancelCalls, 0);
      expect(out.failure, SmartWriteFailure.cancelled);
    });

    test('a hanging request times out and is aborted', () {
      fakeAsync((async) {
        engine
          ..pending = Completer<String>()
          // A stuck client: the abort does not end the request.
          ..ignoreCancel = true;
        SmartWriteOutcome? out;
        unawaited(
          SmartWriteService(
            engine: engine,
          ).write(instruction: 'x').then((o) => out = o),
        );
        async.elapse(const Duration(seconds: 36));
        expect(out?.failure, SmartWriteFailure.openAiTimeout);
        expect(engine.cancelledJobs, engine.jobs);
      });
    });
  });

  group('preview notes: local quality (D6) and refine (#250)', () {
    final l10n = lookupL10n(const Locale('en'));
    DictationNotice card(SmartWriteDraft draft, {bool local = true}) =>
        smartWriteDraftNotice(
          l10n,
          draft,
          onInsert: () {},
          onDiscard: () {},
          localModel: local,
        );
    List<String> ids(DictationNotice n) => [for (final x in n.notes) x.id];

    test('the notes cross the overlay wire with their ids', () {
      final wire = OverlayNotice.fromMap(
        overlayNoticeFor(
          card(const SmartWriteDraft(text: 'Hi', serial: 1)),
          l10n,
        ).toMap(),
      )!;
      expect(
        [for (final n in wire.notes) n.id],
        ['smart-write-local-quality-hint', kSmartWriteRefineHintId],
      );
      expect(wire.notes.every((n) => n.text.isNotEmpty), isTrue);
    });

    test('OpenAI drafts only offer the refine line', () {
      expect(
        ids(card(const SmartWriteDraft(text: 'Hi', serial: 1), local: false)),
        [kSmartWriteRefineHintId],
      );
    });

    test('a changed target shows neither note', () {
      expect(
        ids(
          card(
            const SmartWriteDraft(text: 'Hi', serial: 1, targetChanged: true),
          ),
        ),
        isEmpty,
      );
    });

    test('after three rounds the limit note replaces the refine line', () {
      expect(
        ids(
          card(
            const SmartWriteDraft(
              text: 'Hi',
              serial: 1,
              rounds: kSmartWriteMaxRefineRounds,
            ),
            local: false,
          ),
        ),
        [kSmartWriteRefineLimitHintId],
      );
    });
  });

  group('SmartWritePreviewNotifier', () {
    late _FakePaster paster;
    late ProviderContainer container;

    setUp(() async {
      paster = _FakePaster();
      container = ProviderContainer(
        overrides: [
          pasterProvider.overrideWithValue(paster),
          smartWriteEnvironmentProvider.overrideWithValue(
            SmartWriteEnvironment(
              wayland: false,
              target: () async => 'editor',
              foreground: () async => const ForegroundWindow(id: 'editor'),
              copy: (_) async => true,
              grab: (_, _) async => true,
              release: () async {},
            ),
          ),
          settingsProvider.overrideWith(_FakeSettings.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
    });

    test('Enter pastes the draft once', () async {
      final preview = container.read(smartWritePreviewProvider.notifier);
      await preview.offer('Hello');
      expect(container.read(smartWritePreviewProvider)?.text, 'Hello');
      expect(await preview.insert(), PasteOutcome.success);
      expect(paster.pasted, ['Hello']);
      expect(container.read(smartWritePreviewProvider), isNull);
      expect(await preview.insert(), isNull);
      expect(paster.pasted, hasLength(1));
    });

    test('Esc discards without inserting', () async {
      final preview = container.read(smartWritePreviewProvider.notifier);
      await preview.offer('Hello');
      preview.discard();
      expect(container.read(smartWritePreviewProvider), isNull);
      expect(await preview.insert(), isNull);
      expect(paster.pasted, isEmpty);
    });

    test('a new draft gets a new serial', () async {
      final preview = container.read(smartWritePreviewProvider.notifier);
      await preview.offer('a');
      final first = container.read(smartWritePreviewProvider)!.serial;
      await preview.offer('a');
      expect(container.read(smartWritePreviewProvider)!.serial, first + 1);
    });

    test('hints are announced with a growing serial', () {
      final notifier = container.read(smartWriteNoticeProvider.notifier)
        ..noSelection();
      final first = container.read(smartWriteNoticeProvider)!;
      expect(first.hint, SmartWriteHint.noSelection);
      notifier.clipboardNotRestored();
      final second = container.read(smartWriteNoticeProvider)!;
      expect(second.hint, SmartWriteHint.clipboardNotRestored);
      expect(second.serial, first.serial + 1);
    });
  });

  group('preset-moved notice (D9 migration)', () {
    test('an existing setup sees it once, a fresh or off one never', () {
      // Settings saved before the update: hotkey on, no flag key yet.
      final existing = SmartModeHotkeySettings.fromMap(const {
        'smart_mode_hotkey_enabled': 'true',
      });
      expect(smartWritePresetMovedNoticeDue(existing), isTrue);

      // After it was shown the flag is stored and read back.
      final shown = SmartModeHotkeySettings.fromMap(
        existing.copyWith(smartWriteMigrationNoticeShown: true).toMap(),
      );
      expect(smartWritePresetMovedNoticeDue(shown), isFalse);

      // Hotkey never turned on: nothing moved, no notice.
      expect(
        smartWritePresetMovedNoticeDue(AppSettings.defaults.smartModeHotkey),
        isFalse,
      );
    });
  });

  for (final locale in L10n.supportedLocales) {
    final l10n = lookupL10n(locale);
    group('smart write l10n (${locale.languageCode})', () {
      test('every write error code has its own message', () {
        for (final f in SmartWriteFailure.values) {
          // Esc: the user already knows, so nothing is shown.
          if (f == SmartWriteFailure.cancelled) continue;
          final msg = localizeRecordingError(l10n, f.errorCode);
          expect(msg, isNot(l10n.errorGeneric), reason: f.errorCode);
          expect(msg.trim(), isNotEmpty);
        }
        for (final code in [
          'smart_write_selection_unknown',
          'smart_write_paste_failed',
          'smart_write_target_changed',
          'smart_write_target_unknown',
          'smart_write_keys_failed',
          'smart_write_preview_timeout',
          'smart_write_clipboard_failed',
          'smart_write_missing_key',
          'smart_write_keyring_locked',
        ]) {
          expect(
            localizeRecordingError(l10n, code),
            isNot(l10n.errorGeneric),
            reason: code,
          );
        }
      });

      test('hint, preview and done texts exist', () {
        expect(l10n.smartWriteHintNoSelection.trim(), isNotEmpty);
        expect(l10n.smartWritePreviewInsertHint.trim(), isNotEmpty);
        expect(l10n.smartWritePreviewDiscardHint.trim(), isNotEmpty);
        expect(
          doneMessageFor('paste', l10n, target: RecordingTarget.smartWrite),
          l10n.overlayDoneSmartWrite,
        );
      });
    });
  }
}
