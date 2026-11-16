// Which words the dictionary is offered after a manual correction (#587).
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/dictionary/correction_term_offer.dart';

void main() {
  String? offer(String before, String after, [String vocabulary = '']) =>
      termToOfferAfterCorrection(
        before: before,
        after: after,
        vocabulary: vocabulary,
      );

  test('offers the corrected spelling of one changed word', () {
    expect(
      offer('we use Cubernetes daily', 'we use Kubernetes daily'),
      'Kubernetes',
    );
  });

  test('offers nothing for a rewrite of many words', () {
    expect(
      offer(
        'we ship the release on friday afternoon',
        'the release goes out next week for everyone',
      ),
      isNull,
    );
  });

  test('offers nothing for a change of case or punctuation only', () {
    expect(offer('see Kubernetes now', 'see kubernetes now'), isNull);
    expect(offer('see Kubernetes now', 'see Kubernetes, now'), isNull);
  });

  test('skips a term the dictionary already holds, case aside', () {
    expect(
      offer(
        'we use Cubernetes daily',
        'we use Kubernetes daily',
        'Acme, kubernetes',
      ),
      isNull,
    );
  });

  test('offers one term when two words were corrected', () {
    expect(
      offer('use Cubernetes with dokker', 'use Kubernetes with Docker'),
      anyOf('Kubernetes', 'Docker'),
    );
  });

  test('offers nothing when nothing changed', () {
    expect(offer('same text', 'same text'), isNull);
  });
}
