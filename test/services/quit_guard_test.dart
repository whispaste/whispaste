/// #1498: every interactive quit path asks first while a dictation runs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/quit_guard.dart';

QuitGuard _guard({
  required bool busy,
  required bool answer,
  required List<String> log,
}) => QuitGuard(
  isBusy: () => busy,
  showWindow: () async => log.add('show'),
  ask: () async {
    log.add('ask');
    return answer;
  },
);

void main() {
  test('idle: quit proceeds without a dialog', () async {
    final log = <String>[];
    expect(
      await _guard(busy: false, answer: false, log: log).allowQuit(),
      isTrue,
    );
    expect(log, isEmpty);
  });

  test('busy + cancel: quit is refused, window shown first', () async {
    final log = <String>[];
    expect(
      await _guard(busy: true, answer: false, log: log).allowQuit(),
      isFalse,
    );
    expect(log, ['show', 'ask']);
  });

  test('busy + confirm: quit proceeds', () async {
    final log = <String>[];
    expect(
      await _guard(busy: true, answer: true, log: log).allowQuit(),
      isTrue,
    );
  });

  test('a second request joins the open dialog', () async {
    final log = <String>[];
    final guard = _guard(busy: true, answer: true, log: log);
    final results = await Future.wait([guard.allowQuit(), guard.allowQuit()]);
    expect(results, [true, true]);
    expect(log.where((e) => e == 'ask'), hasLength(1));
  });

  test('a failing dialog refuses the quit', () async {
    final guard = QuitGuard(
      isBusy: () => true,
      showWindow: () async {},
      ask: () async => throw StateError('no navigator'),
    );
    expect(await guard.allowQuit(), isFalse);
  });

  test(
    'macOS confirmTermination replies false on cancel, true on confirm',
    () async {
      final answers = <bool>[false, true];
      final container = ProviderContainer(
        overrides: [
          quitGuardProvider.overrideWithValue(
            QuitGuard(
              isBusy: () => true,
              showWindow: () async {},
              ask: () async => answers.removeAt(0),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await answerConfirmTermination(container), isFalse);
      expect(await answerConfirmTermination(container), isTrue);
    },
  );
}
