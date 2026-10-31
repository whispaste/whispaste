import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/short_press_hint.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  ShortPressHintNotifier notifier() =>
      container.read(shortPressHintProvider.notifier);

  test('is not due before anything was requested', () {
    expect(container.read(shortPressHintProvider), isFalse);
  });

  test('a press that ended early is not reported outside hold mode', () {
    notifier().request(holdModeOn: false);
    expect(container.read(shortPressHintProvider), isFalse);
  });

  test('in hold mode the hint becomes due', () {
    notifier().request(holdModeOn: true);
    expect(container.read(shortPressHintProvider), isTrue);
  });

  test('consuming the hint clears the due flag', () {
    notifier().request(holdModeOn: true);
    notifier().consume();
    expect(container.read(shortPressHintProvider), isFalse);
  });

  test('is shown at most once per app session', () {
    notifier().request(holdModeOn: true);
    notifier().consume();
    notifier().request(holdModeOn: true);
    expect(container.read(shortPressHintProvider), isFalse);
  });

  test('a request outside hold mode does not use up the one-time hint', () {
    notifier().request(holdModeOn: false);
    notifier().request(holdModeOn: true);
    expect(container.read(shortPressHintProvider), isTrue);
  });
}
