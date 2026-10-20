import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
  // UIA-FND-06: 10 px text was the smallest step in use. The floor is 11 px.
  test('the smallest text stage is at least 11 px', () {
    expect(WpTypography.micro, greaterThanOrEqualTo(11));
  });
}
