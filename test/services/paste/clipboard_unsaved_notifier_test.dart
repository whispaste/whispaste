import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/clipboard_unsaved_notifier.dart';

void main() {
  test('the notice is raised once per session, even after it was cleared', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(clipboardUnsavedNotifierProvider.notifier);

    expect(container.read(clipboardUnsavedNotifierProvider), isFalse);

    notifier.report();
    expect(container.read(clipboardUnsavedNotifierProvider), isTrue);

    notifier.clear();
    expect(container.read(clipboardUnsavedNotifierProvider), isFalse);

    notifier.report();
    expect(
      container.read(clipboardUnsavedNotifierProvider),
      isFalse,
      reason: 'a second paste in the same session must not nag again',
    );
  });
}
