import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/modifier_only_flow.dart';

void main() {
  test('macOS suggests Fn, whose Globe key does nothing in WhisPaste', () {
    expect(modifierOnlySuggestion(isMacOS: true), 'fn');
  });

  test('other platforms suggest right Control, not AltGr', () {
    expect(modifierOnlySuggestion(isMacOS: false), 'rightControl');
  });
}
