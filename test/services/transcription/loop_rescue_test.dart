import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/transcription/continuity_guard.dart';
import 'package:whispaste/services/transcription/loop_rescue.dart';

void main() {
  String rep(String phrase, int n) => List.filled(n, phrase).join(' ');
  const clean =
      'Heute habe ich mit dem Team über den Zeitplan gesprochen und wir '
      'haben beschlossen, dass die Abnahme nächste Woche stattfindet.';

  group('shouldRescueLoop', () {
    test('clean text costs no second pass', () {
      expect(shouldRescueLoop(clean), isFalse);
      expect(shouldRescueLoop(''), isFalse);
    });

    test('long phrase loop triggers', () {
      expect(shouldRescueLoop('$clean ${rep('und dann nicht', 5)}'), isTrue);
    });

    test('single-word runaway triggers once past the minimum length', () {
      expect(shouldRescueLoop('$clean ${rep('ja', 8)}'), isTrue);
    });

    test('short stutter below the minimum length does not trigger', () {
      final short = rep('ja', 6);
      expect(isRepetitionLoop(short), isTrue);
      expect(short.split(' ').length, lessThan(kLoopRescueMinWords));
      expect(shouldRescueLoop(short), isFalse);
    });

    test('threshold sits exactly at the minimum word count', () {
      final atMin = rep('ja', kLoopRescueMinWords);
      final below = rep('ja', kLoopRescueMinWords - 1);
      expect(shouldRescueLoop(atMin), isTrue);
      expect(shouldRescueLoop(below), isFalse);
    });

    test('ordinary "ja ja ja" in a sentence does not trigger', () {
      expect(shouldRescueLoop('$clean ja ja ja und weiter'), isFalse);
    });
  });

  group('pickRescued', () {
    final looped = '$clean ${rep('ja', 8)}';
    test('clean retry wins', () {
      expect(pickRescued(first: looped, retry: clean), clean);
    });
    test('looping or empty retry keeps the first result', () {
      expect(pickRescued(first: looped, retry: rep('ja', 9)), looped);
      expect(pickRescued(first: looped, retry: '  '), looped);
    });
  });

  group('continuity guard unchanged', () {
    test('looping piece still carries nothing', () {
      expect(continuityCarryFor(rep('ja', 8)), isNull);
      expect(continuityCarryFor(clean), isNotNull);
    });
  });
}
