import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_name_changes.dart';

/// A distinct capitalised pseudo name for [index] (perf input).
String _name(int index, {String head = 'Zo'}) {
  final buffer = StringBuffer(head);
  var rest = index;
  do {
    buffer.writeCharCode(97 + rest % 26);
    rest ~/= 26;
  } while (rest > 0);
  return buffer.toString();
}

/// Two texts of [count] names, every second name replaced. The lead-in keeps
/// the first name out of sentence-initial position on both sides.
(String, String) _texts(int count) {
  final before = [for (var i = 0; i < count; i++) _name(i + 1)].join(' ');
  final after = [
    for (var i = 0; i < count; i++)
      i.isEven ? _name(i + 1, head: 'Mo') : _name(i + 1),
  ].join(' ');
  return ('Ich sah $before', 'Ich sah $after');
}

void main() {
  test('20k names give exactly the expected pairs', () {
    final (before, after) = _texts(20000);
    final changes = smartModeNameChanges(
      before: before,
      after: after,
      singleCapitalisedWordsAreNames: true,
    );
    expect(changes, hasLength(10000));
    expect(changes.every((c) => c.from != null && c.to != null), isTrue);
  });

  test(
    'a hung isolate yields no summary instead of blocking (GS-045)',
    () async {
      final (before, after) = _texts(5000);
      // Above the isolate threshold, with a timeout that cannot be met.
      final result = await checkSmartModeNameChanges(
        before: before,
        after: after,
        singleCapitalisedWordsAreNames: true,
        timeout: Duration.zero,
      );
      expect(result, isNull);
    },
  );

  test(
    'the isolate path returns the same changes as the direct diff',
    () async {
      final (before, after) = _texts(3000);
      expect(before.length + after.length, greaterThan(20000));

      final direct = smartModeNameChanges(
        before: before,
        after: after,
        singleCapitalisedWordsAreNames: true,
      );
      final guarded = await checkSmartModeNameChanges(
        before: before,
        after: after,
        singleCapitalisedWordsAreNames: true,
      );

      expect(guarded, isNotNull);
      expect(
        guarded!.map((c) => (c.from, c.to)).toList(),
        direct.map((c) => (c.from, c.to)).toList(),
      );
    },
  );
}
