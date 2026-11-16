import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/paste/desktop_paster.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';
import 'package:whispaste/services/replacements/target_field_learning.dart';
import 'package:whispaste/services/replacements/target_field_span.dart';

/// Answers queued reads in order; the last answer repeats.
class _ScriptedReader implements TargetFieldReader {
  _ScriptedReader(this.answers);

  final List<TargetFieldRead> answers;
  final requestedLengths = <int>[];

  @override
  Future<TargetFieldRead> readInsertedSpan(String expectedText) async {
    requestedLengths.add(expectedText.length);
    final i = requestedLengths.length - 1;
    return answers[i < answers.length ? i : answers.length - 1];
  }
}

TargetFieldRead _text(String text) => TargetFieldRead.readable(text: text);

const _pasted = 'deploy the service to kubernetis today';

class _Settings extends SettingsNotifier {
  _Settings({required this.learning});
  final bool learning;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    behavior: AppSettings.defaults.behavior.copyWith(
      correctionLearningEnabled: learning,
    ),
  );
}

void main() {
  group('targetEditPairs', () {
    TargetEditPair pair(String from, String to, String context) =>
        TargetEditPair(
          sourceText: from,
          targetText: to,
          contextBefore: context,
        );

    test('unchanged text gives no pair, foreign text around is ignored', () {
      expect(
        targetEditPairs(
          _pasted,
          r'$ git push; deploy the service to kubernetis today  ~/repo main',
        ),
        isEmpty,
      );
    });

    test('a change in the middle gives one pair with context in front', () {
      expect(
        targetEditPairs(_pasted, '> deploy the service to Kubernetes today'),
        [pair('kubernetis', 'Kubernetes', 'the service to')],
      );
    });

    test('several changes give one pair each', () {
      expect(
        targetEditPairs(
          'we meet with jon at the bahnhoff tomorrow',
          'We meet with John at the Bahnhof tomorrow',
        ),
        [
          // "we" -> "We" at the sentence start is no pair.
          pair('jon', 'John', 'We meet with'),
          pair('bahnhoff', 'Bahnhof', 'John at the'),
        ],
      );
    });

    test('a click to the start and a change of the first word', () {
      // The caret sits after the first word; text before and after the
      // pasted section is foreign.
      expect(
        targetEditPairs(
          'kubernetis runs the cluster',
          'prompt> Kubernetes runs the cluster and more',
        ),
        [pair('kubernetis', 'Kubernetes', 'prompt>')],
      );
    });

    test('writing on after the pasted text is no correction', () {
      expect(
        targetEditPairs(_pasted, '$_pasted and then the database'),
        isEmpty,
      );
    });

    test('pure insertions and deletions are no replacement', () {
      expect(
        targetEditPairs(_pasted, 'deploy the new service to kubernetis today'),
        isEmpty,
      );
      expect(
        targetEditPairs(_pasted, 'deploy service to kubernetis today'),
        isEmpty,
      );
    });

    test('a case-only change counts mid-sentence, not at a sentence start', () {
      expect(
        targetEditPairs('we flew to berlin today', 'we flew to Berlin today'),
        [pair('berlin', 'Berlin', 'we flew to')],
      );
      expect(
        targetEditPairs('done. then we left', 'done. Then we left'),
        isEmpty,
      );
      expect(targetEditPairs('then we left', 'Then we left'), isEmpty);
    });

    test('pasted text gone (Enter, cleared) gives null', () {
      expect(targetEditPairs(_pasted, r'~/repo $ '), isNull);
      expect(targetEditPairs(_pasted, ''), isNull);
      expect(
        targetEditPairs(_pasted, 'deploy something else entirely'),
        isNull,
      );
    });
  });

  test('case-only target-app pairs pass the candidate rules', () {
    expect(
      extractCorrectionCandidates(
        before: 'berlin',
        after: 'Berlin',
        keepCaseOnly: true,
      ).map((p) => p.targetText),
      ['Berlin'],
    );
    expect(
      extractCorrectionCandidates(before: 'berlin', after: 'Berlin'),
      isEmpty,
    );
  });

  group('TargetFieldRead.fromReply (channel contract)', () {
    test('readable reply', () {
      final r = TargetFieldRead.fromReply({
        'readable': true,
        'text': 'abc',
        'matchesExpected': true,
        'reason': 'ok',
        'pattern': 'ax_selected_range',
      });
      expect(r.readable, isTrue);
      expect(r.text, 'abc');
      expect(r.matchesExpected, isTrue);
    });

    test('runner reason codes map to their group', () {
      const groups = {
        'permission_missing': TargetFieldUnreadableReason.permission,
        'sandbox': TargetFieldUnreadableReason.sandbox,
        'password_field': TargetFieldUnreadableReason.password,
        'no_focus': TargetFieldUnreadableReason.noFocus,
        'own_window': TargetFieldUnreadableReason.noFocus,
        'no_text_pattern': TargetFieldUnreadableReason.noText,
        'no_caret': TargetFieldUnreadableReason.noText,
        'unsupported': TargetFieldUnreadableReason.unsupported,
        'busy': TargetFieldUnreadableReason.busy,
        'uia_unavailable': TargetFieldUnreadableReason.error,
        'uia_error': TargetFieldUnreadableReason.error,
      };
      groups.forEach((code, group) {
        final r = TargetFieldRead.fromReply({
          'readable': false,
          'text': null,
          'matchesExpected': false,
          'reason': code,
        });
        expect(r.readable, isFalse, reason: code);
        expect(r.reason, group, reason: code);
      });
    });

    test('malformed or unknown replies count as error, never readable', () {
      for (final reply in [
        null,
        'text',
        {'readable': true},
        {'readable': false, 'reason': 'whatever'},
      ]) {
        final r = TargetFieldRead.fromReply(reply);
        expect(r.readable, isFalse, reason: '$reply');
        expect(r.reason, TargetFieldUnreadableReason.error, reason: '$reply');
      }
    });
  });

  group('ChannelTargetFieldReader', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.whispaste.inserted_span');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends the pasted text and the slack', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return {'readable': true, 'text': 'x', 'matchesExpected': false};
      });
      final read = await ChannelTargetFieldReader().readInsertedSpan('abc');
      expect(seen?.method, 'readInsertedSpan');
      expect(seen?.arguments, {
        'expectedText': 'abc',
        'slackChars': targetFieldSpanSlack,
        'afterChars': 3 + targetFieldSpanSlack,
      });
      expect(read.readable, isTrue);
    });

    test('a runner without handler reports unsupported', () async {
      final read = await ChannelTargetFieldReader().readInsertedSpan('abc');
      expect(read.reason, TargetFieldUnreadableReason.unsupported);
    });
  });

  group('TargetFieldWatch', () {
    TargetFieldWatchResult run(_ScriptedReader reader, String pasted) {
      late TargetFieldWatchResult result;
      fakeAsync((async) {
        final start = DateTime(2026, 11, 3, 12);
        TargetFieldWatch(
          reader: reader,
          now: () => start.add(async.elapsed),
        ).follow(pasted).then((r) => result = r);
        async.elapse(const Duration(seconds: 70));
      });
      return result;
    }

    test('an unreadable field reports its reason and no signal', () {
      final reader = _ScriptedReader([
        const TargetFieldRead.unreadable(TargetFieldUnreadableReason.noText),
      ]);
      final result = run(reader, _pasted);
      expect(result.reason, TargetFieldUnreadableReason.noText);
      expect(result.signals, isEmpty);
      expect(reader.requestedLengths, hasLength(1));
    });

    test('learns from the last snapshot before the text was sent', () {
      final reader = _ScriptedReader([
        _text('> $_pasted'),
        _text('> deploy the service to Kubernetes today'),
        _text(r'~/repo $ '), // Enter: pasted text gone
      ]);
      final result = run(reader, _pasted);
      expect(result.reason, isNull);
      expect(result.signals, hasLength(1));
      final signal = result.signals.single;
      expect(signal.source, CorrectionSignalSource.targetAppEdit);
      expect(signal.sourceText, 'kubernetis');
      expect(signal.targetText, 'Kubernetes');
      expect(signal.contextBefore, 'the service to');
      expect(reader.requestedLengths, everyElement(_pasted.length));
    });

    test('focus moved to another field keeps the last snapshot', () {
      final reader = _ScriptedReader([
        _text('deploy the service to Kubernetes today'),
        const TargetFieldRead.unreadable(TargetFieldUnreadableReason.noFocus),
      ]);
      final result = run(reader, _pasted);
      expect(result.reason, isNull);
      expect(result.signals.single.targetText, 'Kubernetes');
      expect(reader.requestedLengths, hasLength(2));
    });

    test('a busy runner is asked again on the next tick', () {
      final reader = _ScriptedReader([
        const TargetFieldRead.unreadable(TargetFieldUnreadableReason.busy),
        _text('deploy the service to Kubernetes today'),
        _text(''),
      ]);
      final result = run(reader, _pasted);
      expect(result.signals, hasLength(1));
      expect(reader.requestedLengths, hasLength(3));
    });

    test('follows at most the window, then evaluates', () {
      final reader = _ScriptedReader([_text(_pasted)]);
      final result = run(reader, _pasted);
      expect(result.reason, isNull);
      expect(result.signals, isEmpty);
      // 0.8 s first look, then every 3 s until 60 s have passed.
      expect(reader.requestedLengths.length, inInclusiveRange(20, 22));
    });

    test('long transcripts are not watched', () {
      final reader = _ScriptedReader([_text('x')]);
      final result = run(reader, 'a' * (targetFieldMaxInsertedChars + 1));
      expect(result.skipped, isTrue);
      expect(reader.requestedLengths, isEmpty);
    });
  });

  group('targetFieldWatchLogLine (#934)', () {
    test('names app, reason and change count', () {
      expect(
        targetFieldWatchLogLine(app: 'dev.warp.Warp-Stable', changes: 2),
        'Target field watch: app=dev.warp.Warp-Stable, reason=readable, '
        'changes=2',
      );
      expect(
        targetFieldWatchLogLine(
          app: 'com.apple.TextEdit',
          reason: TargetFieldUnreadableReason.sandbox,
        ),
        'Target field watch: app=com.apple.TextEdit, reason=sandbox, '
        'changes=0',
      );
    });

    test('unknown app, skipped watch and paths without folders', () {
      expect(
        targetFieldWatchLogLine(app: null, skipped: true),
        'Target field watch: app=unknown, reason=skipped, changes=0',
      );
      final line = targetFieldWatchLogLine(
        app: r'C:\Users\anna\AppData\Local\Code\Code.exe',
      );
      expect(line, contains('app=Code.exe'));
      expect(line, isNot(contains('anna')));
      expect(
        targetFieldWatchLogLine(app: '/home/anna/bin/kate'),
        contains('app=kate,'),
      );
    });
  });

  group('MAS correction hint (#934)', () {
    test('only the Mac App Store build shows the hint', () {
      expect(masCorrectionHintVisible(isMasBuild: true), isTrue);
      expect(masCorrectionHintVisible(isMasBuild: false), isFalse);
    });

    test('with the hint shown, the log does not repeat the sandbox line', () {
      const byApp = {
        'notes': TargetFieldAppStatus(
          app: 'notes',
          reason: TargetFieldUnreadableReason.sandbox,
        ),
      };
      expect(targetFieldStatusForLog(byApp, isMasBuild: true), isEmpty);
      expect(
        targetFieldStatusForLog(byApp, isMasBuild: false).single.reason,
        TargetFieldUnreadableReason.sandbox,
      );
    });
  });

  group('targetFieldStatusForLog', () {
    TargetFieldStatusNotifier notifierWith(List<TargetFieldAppStatus> s) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(targetFieldStatusProvider.notifier);
      s.forEach(n.record);
      return n;
    }

    List<(String, TargetFieldUnreadableReason?)> shown(
      List<TargetFieldAppStatus> recorded,
    ) => [
      for (final s in targetFieldStatusForLog(notifierWith(recorded).state))
        (s.app, s.reason),
    ];

    test('lists apps newest first, without transient busy reads', () {
      expect(
        shown(const [
          TargetFieldAppStatus(app: 'warp'),
          TargetFieldAppStatus(
            app: 'notes',
            reason: TargetFieldUnreadableReason.noText,
          ),
          TargetFieldAppStatus(
            app: 'edge',
            reason: TargetFieldUnreadableReason.busy,
          ),
          TargetFieldAppStatus(
            app: 'warp',
            reason: TargetFieldUnreadableReason.password,
          ),
        ]),
        [
          ('warp', TargetFieldUnreadableReason.password),
          ('notes', TargetFieldUnreadableReason.noText),
        ],
      );
    });

    test('a reason for every app (sandbox) is one line without an app', () {
      expect(
        shown(const [
          TargetFieldAppStatus(app: 'warp'),
          TargetFieldAppStatus(
            app: 'notes',
            reason: TargetFieldUnreadableReason.sandbox,
          ),
        ]),
        [('', TargetFieldUnreadableReason.sandbox)],
      );
    });

    test('an older global reason gives way once a later read works', () {
      expect(
        shown(const [
          TargetFieldAppStatus(
            app: 'warp',
            reason: TargetFieldUnreadableReason.permission,
          ),
          TargetFieldAppStatus(app: 'notes'),
        ]),
        [('notes', null)],
      );
    });
  });

  group('followTargetFieldAfterPaste', () {
    Future<
      (_ScriptedReader, Map<String, TargetFieldAppStatus>, HistoryDatabase)
    >
    follow({required bool learning}) async {
      final reader = _ScriptedReader([
        _text(_pasted),
        _text('deploy the service to Kubernetes today'),
        _text(''),
      ]);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(learning: learning)),
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          pasterProvider.overrideWithValue(null),
          targetFieldWatchProvider.overrideWith(
            (ref) => TargetFieldWatch(
              reader: reader,
              firstDelay: Duration.zero,
              interval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      await container.read(followTargetFieldProbeProvider(_pasted).future);
      return (reader, container.read(targetFieldStatusProvider), db);
    }

    test('does not read anything with "learn from corrections" off', () async {
      final (reader, status, _) = await follow(learning: false);
      expect(reader.requestedLengths, isEmpty);
      expect(status, isEmpty);
    });

    test(
      'records the status and the changed word with the switch on',
      () async {
        final (reader, status, db) = await follow(learning: true);
        expect(reader.requestedLengths, isNotEmpty);
        expect(status['']?.readable, isTrue);
        expect(status['']?.learned, isTrue);
        final row = await db.readCorrectionObservation(
          normalizeCorrectionKey('kubernetis', 'Kubernetes'),
        );
        expect(row?.source, CorrectionSignalSource.targetAppEdit.name);
      },
    );
  });
}

/// Test-only bridge: runs [followTargetFieldAfterPaste] with a provider [Ref].
final followTargetFieldProbeProvider = FutureProvider.family<void, String>(
  (ref, text) => followTargetFieldAfterPaste(ref, text),
);
