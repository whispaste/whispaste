import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/name_order.dart';

void main() {
  test('German language names sort by base letter (#1845)', () {
    final names = ['Englisch', 'Deutsch', 'Dänisch', 'Chinesisch']
      ..sort(compareDisplayNames);
    expect(names, ['Chinesisch', 'Dänisch', 'Deutsch', 'Englisch']);
  });

  test('case does not split the list', () {
    final names = ['zulu', 'Alpha', 'beta']..sort(compareDisplayNames);
    expect(names, ['Alpha', 'beta', 'zulu']);
  });

  test('ties stay total', () {
    expect(compareDisplayNames('Ä', 'A'), isNot(0));
  });
}
