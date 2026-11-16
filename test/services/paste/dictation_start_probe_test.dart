import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/dictation_start_probe.dart';
import 'package:whispaste/services/replacements/target_field_span.dart';

class _Reader implements CaretTextReader {
  _Reader(this.answer);

  final Future<TargetFieldRead> answer;
  int? asked;

  @override
  Future<TargetFieldRead> readBeforeCaret(int chars) {
    asked = chars;
    return answer;
  }
}

DictationStartProbe _probe(
  Future<TargetFieldRead> answer, {
  Future<Iterable<String>> Function()? terms,
}) => DictationStartProbe.start(
  _Reader(answer),
  terms ?? () async => const <String>[],
);

void main() {
  test('a readable field fits the text', () async {
    final probe = _probe(
      Future.value(const TargetFieldRead.readable(text: 'Wir kommen ')),
    );
    expect(await probe.fit('Und dann', languageCode: 'de'), 'und dann');
  });

  test('dictionary terms reach the rule', () async {
    final probe = _probe(
      Future.value(const TargetFieldRead.readable(text: 'Wir kommen ')),
      terms: () async => const ['Und'],
    );
    expect(await probe.fit('Und dann', languageCode: 'de'), 'Und dann');
  });

  test('an unreadable field leaves the text alone', () async {
    final probe = _probe(
      Future.value(
        const TargetFieldRead.unreadable(TargetFieldUnreadableReason.sandbox),
      ),
    );
    expect(await probe.fit('Und dann', languageCode: 'de'), 'Und dann');
  });

  test('a field without a caret leaves the text alone', () async {
    final probe = _probe(
      Future.value(
        const TargetFieldRead.readable(text: 'Wir kommen ', hasCaret: false),
      ),
    );
    expect(await probe.fit('Und dann', languageCode: 'de'), 'Und dann');
  });

  test('a failing reader or dictionary leaves the text alone', () async {
    final broken = _probe(Future.error(StateError('channel gone')));
    expect(await broken.fit('Und dann', languageCode: 'de'), 'Und dann');

    final noTerms = _probe(
      Future.value(const TargetFieldRead.readable(text: 'Wir kommen ')),
      terms: () async => throw StateError('no database'),
    );
    expect(await noTerms.fit('Und dann', languageCode: 'de'), 'Und dann');
  });

  test('a dictionary that fails during a slow read stays handled', () async {
    final read = Completer<TargetFieldRead>();
    final probe = _probe(
      read.future,
      terms: () async => throw StateError('no database'),
    );
    await Future<void>.delayed(Duration.zero);
    read.complete(const TargetFieldRead.readable(text: 'Wir kommen '));
    expect(await probe.fit('Und dann', languageCode: 'de'), 'Und dann');
  });

  test('a read that finished earlier costs no waiting time', () {
    fakeAsync((time) {
      final probe = _probe(
        Future.value(const TargetFieldRead.readable(text: 'Wir kommen ')),
      );
      time.elapse(const Duration(seconds: 1));

      String? result;
      unawaited(
        probe.fit('Und dann', languageCode: 'de').then((v) => result = v),
      );
      time.flushMicrotasks();
      expect(result, 'und dann');
    });
  });

  test('a slow field releases the text at the limit, unchanged', () {
    fakeAsync((time) {
      final never = Completer<TargetFieldRead>();
      final probe = _probe(never.future);

      String? result;
      unawaited(
        probe.fit('Und dann', languageCode: 'de').then((v) => result = v),
      );
      time.elapse(kDictationStartWait - const Duration(milliseconds: 1));
      expect(result, isNull);
      time.elapse(const Duration(milliseconds: 1));
      expect(result, 'Und dann');
    });
  });

  test('the channel reply tells a caret read from a section of the field', () {
    Map<String, Object> reply(String? pattern) => {
      'readable': true,
      'text': 'Wir kommen ',
      'pattern': ?pattern,
    };
    expect(
      TargetFieldRead.fromReply(reply('ax_selected_range')).hasCaret,
      true,
    );
    expect(TargetFieldRead.fromReply(reply(null)).hasCaret, true);
    expect(TargetFieldRead.fromReply(reply('ax_value')).hasCaret, false);
    expect(TargetFieldRead.fromReply(reply('atspi_tail')).hasCaret, false);
  });
}
