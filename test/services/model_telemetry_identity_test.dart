import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/telemetry/onboarding_telemetry_buffer.dart';
import 'package:whispaste/services/model_hardware_telemetry.dart';
import 'package:whispaste/services/dictation_quality_telemetry.dart';
import 'package:whispaste/services/model_telemetry_identity.dart';
import 'package:whispaste/services/telemetry_service.dart'
    show
        TelemetrySessionAggregator,
        onboardingTelemetryBufferProvider,
        telemetrySessionAggregatorProvider;
import 'package:whispaste/services/undo_shortcut_probe.dart';
import 'package:whispaste/services/user_models/user_model.dart';

const _sha = 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb';

/// The native watch as the hosts implement it: one flag, armed by [watch]
/// until [take] or the next [watch]; a press only counts while armed.
class _FakeUndoShortcutProbe implements UndoShortcutProbe {
  _FakeUndoShortcutProbe({required this.supported});

  final bool supported;
  bool watching = false;
  bool _seen = false;
  int watchCalls = 0;
  int takeCalls = 0;

  void press() {
    if (watching) _seen = true;
  }

  @override
  Future<UndoShortcutWatchStart> watch(Duration window) async {
    watchCalls++;
    final seen = _seen;
    _seen = false;
    watching = supported;
    return (watching: supported, seen: seen);
  }

  @override
  Future<bool> take() async {
    takeCalls++;
    final seen = _seen;
    _seen = false;
    watching = false;
    return seen;
  }
}

OwnModelFacts _own({String? url, String sha = _sha}) => OwnModelFacts(
  runtime: 'whispercpp',
  family: 'whisper',
  sizeBytes: 574041195,
  sha256: sha,
  sourceUrl: url,
);

/// Pieces of an address that must never reach an event.
const _secrets = [
  'hf_SECRETTOKEN',
  'alice',
  'pa55',
  'Users',
  'home',
  'C:',
  '8443',
  'download=1',
];

void _expectNoSecret(String value) {
  for (final s in _secrets) {
    expect(value, isNot(contains(s)), reason: '"$value" leaks "$s"');
  }
}

void main() {
  group('model key: Hugging Face', () {
    test('owner, repo and file name, revision and folders dropped', () {
      expect(
        ownModelSourceKey(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
          '5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin',
        ),
        'hf:ggerganov/whisper.cpp/ggml-small-q5_1.bin',
      );
      expect(
        ownModelSourceKey(
          'https://hf.co/org/model-de/blob/main/sub/dir/model.gguf',
        ),
        'hf:org/model-de/model.gguf',
      );
    });

    test('query, fragment, credentials and port never reach the key', () {
      final key = ownModelSourceKey(
        'https://alice:pa55@huggingface.co:8443/org/repo/resolve/main/'
        'model.bin?token=hf_SECRETTOKEN&download=1#x',
      );
      expect(key, 'hf:org/repo/model.bin');
      _expectNoSecret(key!);
    });

    test('a non-file Hugging Face address is a plain host key', () {
      expect(
        ownModelSourceKey('https://huggingface.co/org/repo'),
        'url:huggingface.co/repo',
      );
    });
  });

  group('model key: direct address', () {
    test('host and file name only', () {
      expect(
        ownModelSourceKey(
          'https://alice:pa55@models.example.org:8443/alice/private/'
          'my-model.bin?sig=hf_SECRETTOKEN',
        ),
        'url:models.example.org/my-model.bin',
      );
    });

    test('an unusual file name is left out, the host stays', () {
      expect(
        ownModelSourceKey('https://cdn.example.com/files/my%20model.bin'),
        'url:cdn.example.com',
      );
      expect(
        ownModelSourceKey('https://cdn.example.com/'),
        'url:cdn.example.com',
      );
    });

    test('no http(s) address: no source key', () {
      expect(ownModelSourceKey(null), isNull);
      expect(ownModelSourceKey('file:///Users/alice/model.bin'), isNull);
      expect(ownModelSourceKey('/home/alice/model.bin'), isNull);
      expect(ownModelSourceKey(r'C:\Users\alice\model.bin'), isNull);
      expect(ownModelSourceKey('not a url'), isNull);
    });
  });

  group('model key: imported file', () {
    test('only a hash prefix, never a path or file name', () {
      expect(ownModelKey(_own()), 'local:ae85e4a935d7');
      final key = ownModelKey(_own(url: 'file:///Users/alice/model.bin'));
      expect(key, 'local:ae85e4a935d7');
      _expectNoSecret(key);
      expect(ownModelKey(_own(sha: 'nope')), 'local:unknown');
    });
  });

  group('own model details', () {
    test('runtime, family, size class and full hash', () {
      expect(ownModelDetails(_own()), 'whispercpp|whisper|500m_1g|$_sha');
      expect(
        modelEventName('hf:o/r/f.bin', own: _own()),
        'hf:o/r/f.bin|whispercpp|whisper|500m_1g|$_sha',
      );
      expect(modelEventName('small'), 'small');
    });

    test('free text in runtime or family becomes other', () {
      const facts = OwnModelFacts(
        runtime: 'C:/Users/alice',
        family: 'my family',
        sizeBytes: 0,
        sha256: 'xyz',
      );
      expect(ownModelDetails(facts), 'other|other|unknown|unknown');
    });

    test('size class edges', () {
      expect(modelSizeBucket(99999999), 'lt100m');
      expect(modelSizeBucket(100000000), '100m_500m');
      expect(modelSizeBucket(999999999), '500m_1g');
      expect(modelSizeBucket(1000000000), '1g_2g');
      expect(modelSizeBucket(2000000000), 'gt2g');
    });
  });

  group('negative list gate', () {
    test('accepts every key and event name the app builds', () {
      for (final v in [
        'small',
        'large-v3-turbo|8_16-gpu-gpu|ok|lt0_5',
        'parakeet|load_failed|timeout|cpu',
        'medium>small|oom',
        'hf:ggerganov/whisper.cpp/ggml-small-q5_1.bin|whisper|whisper|500m_1g|$_sha',
        'url:models.example.org/my-model.bin|gt16-nogpu-cpu|fail|na',
        'url:models.example.org',
        'local:ae85e4a935d7|lt8-gpu-cpu',
        'small|failed|offline|s2',
      ]) {
        expect(isTelemetrySafeName(v), isTrue, reason: v);
      }
    });

    test('rejects addresses, queries, credentials, paths and free text', () {
      for (final v in [
        'https://huggingface.co/a/b/resolve/main/c.bin',
        'url:host.com/f.bin?token=x',
        'url:alice@host.com/f.bin',
        'url:host.com/dir/f.bin',
        'hf:a/b',
        '/Users/alice/model.bin',
        'local:/home/alice/m.bin',
        r'C:\Users\alice\m.bin',
        'C:/Users/alice/m.bin',
        '~/m.bin',
        'small|../../etc',
        'my model',
        'a%20b',
        'x' * 241,
        '',
      ]) {
        expect(isTelemetrySafeName(v), isFalse, reason: v);
      }
    });
  });

  group('dictation quality', () {
    test('device class: RAM, GPU present, where it ran', () {
      expect(
        deviceTier(ramClass: '8_16', hasGpu: true, ranOnGpu: false),
        '8_16-gpu-cpu',
      );
      expect(
        deviceTier(ramClass: 'lt8', hasGpu: false, ranOnGpu: false),
        'lt8-nogpu-cpu',
      );
      expect(backendIsGpu('metal'), isTrue);
      expect(backendIsGpu('cpu'), isFalse);
      expect(backendIsGpu(null), isFalse);
    });

    test('quality name; a failure has no speed class', () {
      expect(
        dictationQualityName(
          modelKey: 'small',
          device: 'lt8-nogpu-cpu',
          ok: true,
          rtf: '0_5_1_5',
        ),
        'small|lt8-nogpu-cpu|ok|0_5_1_5',
      );
      expect(
        dictationQualityName(
          modelKey: 'small',
          device: 'lt8-nogpu-cpu',
          ok: false,
          rtf: null,
        ),
        'small|lt8-nogpu-cpu|fail|na',
      );
    });

    test('quick repeat within the window only', () {
      final t = DateTime(2026, 11, 17, 12);
      expect(isQuickRedictation(lastInsertedAt: null, startedAt: t), isFalse);
      expect(
        isQuickRedictation(
          lastInsertedAt: t,
          startedAt: t.add(kQuickRedictationWindow),
        ),
        isTrue,
      );
      expect(
        isQuickRedictation(
          lastInsertedAt: t,
          startedAt: t.add(
            kQuickRedictationWindow + const Duration(milliseconds: 1),
          ),
        ),
        isFalse,
      );
      expect(
        isQuickRedictation(
          lastInsertedAt: t,
          startedAt: t.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  group('lifecycle helpers', () {
    test('download failure names the source number, never the source', () {
      expect(
        downloadFailureName(
          modelKey: 'small',
          kind: 'offline',
          sourceNumber: 2,
        ),
        'small|failed|offline|s2',
      );
      expect(
        downloadFailureName(modelKey: 'small', kind: 'tls', sourceNumber: null),
        'small|failed|tls|s0',
      );
    });

    test('removed models and delete errors', () {
      expect(removedModelIds({'a', 'b'}, {'b'}), {'a'});
      expect(isDeleteError(null), isFalse);
    });

    test('own model key via the lookup, catalog id otherwise', () {
      OwnModelFacts? lookup(String id) =>
          id == 'user-1234abcd' ? _own(url: null) : null;
      final own = AppSettings.defaults.copyWith(
        sttProvider: 'On Device',
        sttEngine: 'whisper',
        sttModel: 'user-1234abcd',
      );
      final catalog = own.copyWith(sttModel: 'whisper-small');
      expect(telemetryModelKey(lookup, own), 'local:ae85e4a935d7');
      expect(activeOwnModel(lookup, own), isNotNull);
      expect(telemetryModelKey(lookup, catalog), 'small');
      expect(activeOwnModel(lookup, catalog), isNull);
      // Without the own-model store, an own model stays `other`.
      expect(telemetryModelKey((_) => null, own), 'other');
    });
  });

  group('lifecycle events: buffer and gate', () {
    (ModelLifecycleTelemetry, List<String>, OnboardingTelemetryBuffer)
    setUpEvents() {
      final sent = <String>[];
      final buffer = OnboardingTelemetryBuffer(
        send: (e) => sent.add('${e.category}/${e.action}/${e.name}'),
      );
      final container = ProviderContainer(
        overrides: [
          onboardingTelemetryBufferProvider.overrideWithValue(buffer),
        ],
      );
      addTearDown(container.dispose);
      return (container.read(modelLifecycleTelemetryProvider), sent, buffer);
    }

    test('sent as they happen outside a first run', () {
      final (events, sent, _) = setUpEvents();
      events.installed('small');
      events.activated('local:ae85e4a935d7', own: _own());
      events.checkFailed('small', ModelCheck.shortTest);
      events.loadFailed('parakeet', cause: 'timeout', gpu: true);
      events.fallback(fromKey: 'medium', toKey: 'small', reason: 'oom');
      events.removed('small');
      expect(sent, [
        'model/installed/small',
        'model/activated/local:ae85e4a935d7|whispercpp|whisper|500m_1g|$_sha',
        'model/check_failed/small|short_test',
        'model/load_failed/parakeet|timeout|gpu',
        'model/fallback/medium>small|oom',
        'model/removed/small',
      ]);
    });

    test('held in a first run, dropped after a no', () {
      final (events, sent, buffer) = setUpEvents();
      buffer.begin();
      events.installed('small');
      expect(sent, isEmpty);
      buffer.decide(shareUsageStats: false);
      expect(sent, isEmpty);
    });

    test('an unsafe value is dropped, never sent', () {
      final (events, sent, _) = setUpEvents();
      events.installed('https://host.example/alice/model.bin?token=x');
      events.removed('/Users/alice/model.bin');
      expect(sent, isEmpty);
    });
  });

  group('own models from user_models.json', () {
    UserModel model({
      required UserModelSourceKind source,
      String? url,
      String? address,
      UserModelRuntime runtime = UserModelRuntime.whispercpp,
      SherpaFamily? family,
      UserModelStatus status = UserModelStatus.ready,
      UserModelFailure? failure,
    }) => UserModel(
      id: 'user-1234abcd',
      name: 'alice model',
      runtime: runtime,
      family: family,
      sourceKind: source,
      sourceAddress: address,
      files: [
        UserModelFile(
          role: UserModelFileRole.model,
          name: 'ggml-small-q5_1.bin',
          url: url,
          sizeBytes: 190000000,
          sha256: _sha,
        ),
      ],
      addedAt: DateTime.utc(2026, 11, 20),
      status: status,
      failure: failure,
    );

    test('Hugging Face: repo and file of the pinned download address', () {
      final facts = ownModelFactsFrom(
        model(
          source: UserModelSourceKind.huggingFace,
          url:
              'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
              '5359861c/ggml-small-q5_1.bin',
          address: 'https://huggingface.co/ggerganov/whisper.cpp',
        ),
      );
      expect(
        ownModelKey(facts),
        'hf:ggerganov/whisper.cpp/ggml-small-q5_1.bin',
      );
      expect(ownModelDetails(facts), 'whispercpp|whisper|100m_500m|$_sha');
    });

    test('direct address: host and file, no query or credentials', () {
      final facts = ownModelFactsFrom(
        model(
          source: UserModelSourceKind.url,
          url:
              'https://alice:pa55@models.example.org:8443/home/alice/'
              'ggml-small-q5_1.bin?token=hf_SECRETTOKEN&download=1',
          address: 'https://alice:pa55@models.example.org/?token=x',
        ),
      );
      final name = modelEventName(ownModelKey(facts), own: facts);
      expect(name, startsWith('url:models.example.org/ggml-small-q5_1.bin|'));
      _expectNoSecret(name);
      expect(isTelemetrySafeName(name), isTrue);
    });

    test('imported file: hash prefix and details only', () {
      final facts = ownModelFactsFrom(
        model(
          source: UserModelSourceKind.file,
          // A local import never has an address; even a stray one is ignored.
          url: 'file:///Users/alice/Downloads/ggml-small-q5_1.bin',
        ),
      );
      final name = modelEventName(ownModelKey(facts), own: facts);
      expect(name, 'local:ae85e4a935d7|whispercpp|whisper|100m_500m|$_sha');
      expect(name, isNot(contains('ggml')));
      _expectNoSecret(name);
    });

    test('family: sherpa family, whisper for GGML, gguf for Smart Mode', () {
      expect(
        ownModelFactsFrom(
          model(
            source: UserModelSourceKind.file,
            runtime: UserModelRuntime.sherpaOnnx,
            family: SherpaFamily.senseVoice,
          ),
        ).family,
        'sense_voice',
      );
      expect(
        ownModelFactsFrom(
          model(
            source: UserModelSourceKind.file,
            runtime: UserModelRuntime.llamaCpp,
          ),
        ).family,
        'gguf',
      );
    });

    test('add result: installed, download counter or failed check', () {
      final sent = <String>[];
      final aggregator = TelemetrySessionAggregator();
      final container = ProviderContainer(
        overrides: [
          onboardingTelemetryBufferProvider.overrideWithValue(
            OnboardingTelemetryBuffer(
              send: (e) => sent.add('${e.category}/${e.action}/${e.name}'),
            ),
          ),
          telemetrySessionAggregatorProvider.overrideWithValue(aggregator),
        ],
      );
      addTearDown(container.dispose);
      final events = container.read(modelLifecycleTelemetryProvider);
      events.ownModelAdded(model(source: UserModelSourceKind.file));
      events.ownModelAdded(
        model(
          source: UserModelSourceKind.file,
          status: UserModelStatus.failed,
          failure: UserModelFailure.shortTestFailed,
        ),
      );
      events.ownModelAdded(
        model(
          source: UserModelSourceKind.file,
          status: UserModelStatus.failed,
          failure: UserModelFailure.fileChanged,
        ),
      );
      events.ownModelAdded(
        model(
          source: UserModelSourceKind.file,
          status: UserModelStatus.failed,
          failure: UserModelFailure.download,
        ),
      );
      events.ownModelAdded(
        model(
          source: UserModelSourceKind.file,
          status: UserModelStatus.checking,
        ),
      );
      expect(sent, [
        'model/installed/local:ae85e4a935d7|whispercpp|whisper|100m_500m|$_sha',
        'model/check_failed/local:ae85e4a935d7|short_test_failed',
        'model/check_failed/local:ae85e4a935d7|hash',
      ]);
      expect(aggregator.debugCounts, {
        ('model', 'download', 'local:ae85e4a935d7|failed|network|s1'): 1,
      });
    });
  });

  group('model keys of ids, fallbacks and Smart Mode', () {
    OwnModelFacts? lookup(String id) =>
        id == 'user-1234abcd' ? _own(url: null) : null;

    test('speech model id', () {
      expect(modelKeyForId(lookup, 'whisper-medium'), 'medium');
      expect(modelKeyForId(lookup, 'user-1234abcd'), 'local:ae85e4a935d7');
      expect(modelKeyForId(lookup, 'user-gone0000'), 'other');
    });

    test('fallback target', () {
      expect(fallbackChoiceKey(null), 'none');
      expect(
        fallbackChoiceKey(
          const SpeechFallbackChoice(
            engine: 'whisper',
            modelId: 'whisper-small',
          ),
        ),
        'small',
      );
      expect(
        fallbackChoiceKey(
          const SpeechFallbackChoice(engine: 'parakeet', modelId: ''),
        ),
        'parakeet',
      );
    });

    test('Smart Mode text model', () {
      final local = AppSettings.defaults.copyWithSections(
        smartMode: AppSettings.defaults.smartMode.copyWith(
          provider: 'local',
          localModel: '',
        ),
      );
      expect(smartModeModelKey(lookup, local), 'gemma');
      final own = local.copyWithSections(
        smartMode: local.smartMode.copyWith(localModel: 'user-1234abcd'),
      );
      expect(smartModeModelKey(lookup, own), 'local:ae85e4a935d7');
      final cloud = local.copyWithSections(
        smartMode: local.smartMode.copyWith(provider: 'openai'),
      );
      expect(smartModeModelKey(lookup, cloud), isNull);
    });

    test('a user_model fallback carries its failure', () {
      final sent = <String>[];
      final container = ProviderContainer(
        overrides: [
          onboardingTelemetryBufferProvider.overrideWithValue(
            OnboardingTelemetryBuffer(
              send: (e) => sent.add('${e.category}/${e.action}/${e.name}'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(modelLifecycleTelemetryProvider)
          .fallback(
            fromKey: 'local:ae85e4a935d7',
            toKey: 'small',
            reason: 'user_model',
            detail: 'failed_in_use',
          );
      expect(sent, [
        'model/fallback/local:ae85e4a935d7>small|user_model|failed_in_use',
      ]);
    });
  });

  group('dictation quality counters', () {
    const context = (
      modelKey: 'hf:org/repo/model.bin',
      backend: 'metal',
      device: 'gt16-gpu-gpu',
    );

    (
      DictationQualityTelemetry,
      TelemetrySessionAggregator,
      void Function(Duration),
    )
    setUpQuality() {
      var now = DateTime(2026, 11, 20, 12);
      final aggregator = TelemetrySessionAggregator();
      final container = ProviderContainer(
        overrides: [
          telemetrySessionAggregatorProvider.overrideWithValue(aggregator),
          dictationQualityTelemetryProvider.overrideWith(
            (ref) => DictationQualityTelemetry(ref, clock: () => now),
          ),
        ],
      );
      addTearDown(container.dispose);
      return (
        container.read(dictationQualityTelemetryProvider),
        aggregator,
        (d) => now = now.add(d),
      );
    }

    test('outcome per model and device; a failure has no speed class', () {
      final (quality, aggregator, _) = setUpQuality();
      quality.countOutcome(context, ok: true, rtf: 'lt0_5');
      quality.countOutcome(context, ok: false, rtf: 'lt0_5');
      expect(aggregator.debugCounts, {
        ('model', 'dictation', 'hf:org/repo/model.bin|gt16-gpu-gpu|ok|lt0_5'):
            1,
        ('model', 'dictation', 'hf:org/repo/model.bin|gt16-gpu-gpu|fail|na'): 1,
      });
    });

    test('a quick repeat counts once for the pasted model', () {
      final (quality, aggregator, advance) = setUpQuality();
      quality.rememberPaste(context);
      advance(const Duration(seconds: 5));
      quality.dictationStarted();
      quality.dictationStarted();
      quality.rememberPaste(context);
      advance(kQuickRedictationWindow + const Duration(seconds: 1));
      quality.dictationStarted();
      expect(aggregator.debugCounts, {
        ('model', 'redictate', 'hf:org/repo/model.bin|gt16-gpu-gpu'): 1,
      });
    });

    test('recordUndoAfterPaste counts the pasted model with its source', () {
      final (quality, aggregator, advance) = setUpQuality();
      quality.rememberPaste(context);
      advance(const Duration(seconds: 3));
      quality.recordUndoAfterPaste(UndoAfterPasteSource.smartMode);
      // The undone paste is no longer a candidate for a quick repeat.
      quality.dictationStarted();
      expect(aggregator.debugCounts, {
        ('model', 'undo', 'hf:org/repo/model.bin|gt16-gpu-gpu|smart_mode'): 1,
      });
    });

    test('an unsafe model key is dropped, never counted', () {
      final (quality, aggregator, _) = setUpQuality();
      quality.countOutcome(
        (
          modelKey: 'C:\\Users\\alice\\model.bin',
          backend: 'cpu',
          device: 'lt8-nogpu-cpu',
        ),
        ok: true,
        rtf: null,
      );
      expect(aggregator.debugCounts, isEmpty);
    });

    group('undo shortcut watch (#2078)', () {
      const other = (
        modelKey: 'parakeet-tdt-0.6b-v3',
        backend: 'cpu',
        device: 'lt8-nogpu-cpu',
      );
      const shortcut = 'hf:org/repo/model.bin|gt16-gpu-gpu|shortcut';
      const otherShortcut = 'parakeet-tdt-0.6b-v3|lt8-nogpu-cpu|shortcut';

      /// Runs [body] with a fake native watch in fake time.
      void inWatch(
        void Function(
          DictationQualityTelemetry quality,
          TelemetrySessionAggregator aggregator,
          _FakeUndoShortcutProbe probe,
          FakeAsync async,
        )
        body, {
        bool supported = true,
      }) {
        fakeAsync((async) {
          final start = DateTime(2026, 11, 20, 12);
          final aggregator = TelemetrySessionAggregator();
          final probe = _FakeUndoShortcutProbe(supported: supported);
          final container = ProviderContainer(
            overrides: [
              telemetrySessionAggregatorProvider.overrideWithValue(aggregator),
              undoShortcutProbeProvider.overrideWithValue(probe),
              dictationQualityTelemetryProvider.overrideWith(
                (ref) => DictationQualityTelemetry(
                  ref,
                  clock: () => start.add(async.elapsed),
                ),
              ),
            ],
          );
          body(
            container.read(dictationQualityTelemetryProvider),
            aggregator,
            probe,
            async,
          );
          container.dispose();
        });
      }

      int count(TelemetrySessionAggregator a, String action, String name) =>
          a.debugCounts[('model', action, name)] ?? 0;

      test('an undo shortcut in the window counts once for that paste', () {
        inWatch((quality, aggregator, probe, async) {
          quality.rememberPaste(context, watchShortcut: true);
          async.flushMicrotasks();
          expect(probe.watching, isTrue);
          async.elapse(const Duration(seconds: 4));
          probe.press();
          probe.press();
          async.elapse(kUndoShortcutWindow);
          expect(probe.watching, isFalse, reason: 'ends after the window');
          expect(count(aggregator, 'undo', shortcut), 1);
          expect(
            count(
              aggregator,
              'undo_watch',
              'hf:org/repo/model.bin|gt16-gpu-gpu|watched',
            ),
            1,
          );
          // The undone paste is no quick repeat any more.
          quality.dictationStarted();
          expect(count(aggregator, 'redictate', context.modelKey), 0);
        });
      });

      test('no watch without the flag, and none after the window', () {
        inWatch((quality, aggregator, probe, async) {
          quality.rememberPaste(context);
          async.flushMicrotasks();
          expect(probe.watchCalls, 0);
          quality.rememberPaste(context, watchShortcut: true);
          async.elapse(kUndoShortcutWindow + const Duration(seconds: 2));
          probe.press();
          async.elapse(const Duration(minutes: 1));
          expect(probe.watching, isFalse);
          expect(count(aggregator, 'undo', shortcut), 0);
        });
      });

      test('paste after paste: each undo goes to the model that pasted', () {
        inWatch((quality, aggregator, probe, async) {
          quality.rememberPaste(context, watchShortcut: true);
          async.flushMicrotasks();
          probe.press();
          // The next paste ends the first watch and reports its undo.
          quality.rememberPaste(other, watchShortcut: true);
          async.flushMicrotasks();
          expect(count(aggregator, 'undo', shortcut), 1);
          expect(count(aggregator, 'undo', otherShortcut), 0);
          probe.press();
          // A paste without a watch still collects the running one.
          quality.rememberPaste(context);
          async.flushMicrotasks();
          expect(probe.watching, isFalse);
          expect(count(aggregator, 'undo', otherShortcut), 1);
          expect(count(aggregator, 'undo', shortcut), 1);
        });
      });

      test('a WhisPaste undo settles the paste: its shortcut does not '
          'count again', () {
        inWatch((quality, aggregator, probe, async) {
          quality.rememberPaste(context, watchShortcut: true);
          async.flushMicrotasks();
          probe.press(); // the shortcut the WhisPaste undo sends itself
          quality.recordUndoAfterPaste(UndoAfterPasteSource.smartMode);
          async.elapse(kUndoShortcutWindow * 2);
          expect(probe.watching, isFalse);
          expect(count(aggregator, 'undo', shortcut), 0);
          expect(
            count(
              aggregator,
              'undo',
              'hf:org/repo/model.bin|gt16-gpu-gpu|smart_mode',
            ),
            1,
          );
        });
      });

      test('consent withdrawn: the watch ends and counts nothing', () {
        inWatch((quality, aggregator, probe, async) {
          quality.rememberPaste(context, watchShortcut: true);
          async.flushMicrotasks();
          probe.press();
          quality.stopShortcutWatch();
          async.elapse(kUndoShortcutWindow * 2);
          expect(probe.watching, isFalse);
          expect(count(aggregator, 'undo', shortcut), 0);
        });
      });

      test('a platform that cannot watch reports unknown', () {
        inWatch(supported: false, (quality, aggregator, probe, async) {
          quality.rememberPaste(context, watchShortcut: true);
          async.elapse(kUndoShortcutWindow * 2);
          expect(
            count(
              aggregator,
              'undo_watch',
              'hf:org/repo/model.bin|gt16-gpu-gpu|unknown',
            ),
            1,
          );
          expect(probe.takeCalls, 0, reason: 'nothing to collect');
        });
      });
    });

    test('undo window edges', () {
      final t = DateTime(2026, 11, 20, 12);
      expect(isUndoRightAfterPaste(pastedAt: null, now: t), isFalse);
      expect(
        isUndoRightAfterPaste(pastedAt: t, now: t.add(kUndoAfterPasteWindow)),
        isTrue,
      );
      expect(
        isUndoRightAfterPaste(
          pastedAt: t,
          now: t.add(kUndoAfterPasteWindow + const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });
}
