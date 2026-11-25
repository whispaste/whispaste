/// Safeguards of API write jobs (#255, ADR 0015 D22): rate limit, one open
/// job, target check, revocation before the paste, text-free protocol.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/automation_write_jobs.dart';

class _FakeRunner implements AutomationWriteRunner {
  AutomationWriteTarget target = const AutomationWriteTarget(id: 'app.mail');
  String? blocked;
  AutomationWriteDraft draft = const AutomationWriteDraft.text('Hallo Welt');
  String? insertFailure;
  Completer<void>? writeGate;
  final inserted = <String>[];

  @override
  Future<AutomationWriteTarget> captureTarget() async => target;

  @override
  Future<String?> preflight() async => blocked;

  @override
  Future<AutomationWriteDraft> write(
    String instruction,
    AutomationWriteContextLimits limits,
  ) async {
    await writeGate?.future;
    return draft;
  }

  @override
  Future<String?> insert(
    String text,
    AutomationWriteTarget target, {
    required bool Function() stillAllowed,
  }) async {
    if (!stillAllowed()) return 'revoked';
    if (insertFailure != null) return insertFailure;
    inserted.add(text);
    return null;
  }
}

void main() {
  late _FakeRunner runner;
  late DateTime now;
  late ProviderContainer container;

  AutomationWriteJobs jobs() =>
      container.read(automationWriteJobsProvider.notifier);

  setUp(() {
    runner = _FakeRunner();
    now = DateTime(2026, 11, 19, 10);
    container = ProviderContainer(
      overrides: [
        automationWriteRunnerProvider.overrideWithValue(runner),
        automationWriteJobsProvider.overrideWith(
          () => AutomationWriteJobs(clock: () => now),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<AutomationWriteRecord> run(String instruction) {
    final start = jobs().start(instruction);
    expect(start, isA<AutomationWriteStarted>());
    return (start as AutomationWriteStarted).done;
  }

  test('a job pastes the result and logs only sizes', () async {
    final record = await run('Schreib eine Absage');
    expect(record.status, AutomationWriteStatus.inserted);
    expect(runner.inserted, ['Hallo Welt']);
    expect(record.instructionChars, 'Schreib eine Absage'.length);
    expect(record.resultChars, 'Hallo Welt'.length);
    final json = jsonEncode(record.toJson());
    expect(json, isNot(contains('Absage')));
    expect(json, isNot(contains('Hallo')));
  });

  test('one open job at a time', () async {
    runner.writeGate = Completer<void>();
    final first = jobs().start('a') as AutomationWriteStarted;
    expect(jobs().start('b'), isA<AutomationWriteBusy>());
    runner.writeGate!.complete();
    await first.done;
    final third = jobs().start('c');
    expect(third, isA<AutomationWriteStarted>());
    await (third as AutomationWriteStarted).done;
  });

  test('at most ten starts per sliding minute', () async {
    for (var i = 0; i < kAutomationWriteRateLimit; i++) {
      await run('job $i');
      now = now.add(const Duration(seconds: 1));
    }
    final limited = jobs().start('one too many');
    expect(limited, isA<AutomationWriteRateLimited>());
    expect(
      (limited as AutomationWriteRateLimited).retryAfter,
      const Duration(seconds: 50),
    );
    now = now.add(const Duration(seconds: 50));
    await run('again');
  });

  test('revocation while writing: nothing is pasted', () async {
    runner.writeGate = Completer<void>();
    final start = jobs().start('a') as AutomationWriteStarted;
    await Future<void>.delayed(Duration.zero);
    jobs().revokeAll();
    runner.writeGate!.complete();
    final record = await start.done;
    expect(record.status, AutomationWriteStatus.failed);
    expect(record.errorCode, 'revoked');
    expect(runner.inserted, isEmpty);
  });

  test('no checkable target app: the engine is not even asked', () async {
    runner.target = const AutomationWriteTarget();
    runner.writeGate = Completer<void>(); // would hang if write() ran
    final record = await run('a');
    expect(record.errorCode, 'automation_write_target_unknown');
  });

  test('Wayland pastes without a target check and says so', () async {
    runner.target = const AutomationWriteTarget(wayland: true);
    final record = await run('a');
    expect(record.status, AutomationWriteStatus.inserted);
    expect(record.targetChecked, isFalse);
  });

  test('engine not ready and failed paste end as failed', () async {
    runner.blocked = 'smart_write_missing_key';
    expect((await run('a')).errorCode, 'smart_write_missing_key');
    runner
      ..blocked = null
      ..insertFailure = 'automation_write_target_changed';
    final record = await run('b');
    expect(record.status, AutomationWriteStatus.failed);
    expect(record.errorCode, 'automation_write_target_changed');
  });

  test('the protocol keeps the newest twenty jobs', () async {
    for (var i = 0; i < kAutomationWriteProtocolSize + 5; i++) {
      await run('job $i');
      now = now.add(const Duration(minutes: 1));
    }
    final protocol = container.read(automationWriteJobsProvider);
    expect(protocol, hasLength(kAutomationWriteProtocolSize));
    expect(protocol.first.startedAt.isAfter(protocol.last.startedAt), isTrue);
  });
}
