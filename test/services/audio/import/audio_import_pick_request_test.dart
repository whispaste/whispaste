import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';

void main() {
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    now = DateTime(2026, 10, 18, 12);
    container = ProviderContainer(
      overrides: [audioImportClockProvider.overrideWithValue(() => now)],
    );
  });

  tearDown(() => container.dispose());

  AudioImportPickRequestNotifier notifier() =>
      container.read(audioImportPickRequestProvider.notifier);

  test('no request is pending by default', () {
    expect(container.read(audioImportPickRequestProvider), isNull);
    expect(notifier().takeRequest(), isFalse);
  });

  test('a request is taken exactly once', () {
    notifier().request();
    expect(container.read(audioImportPickRequestProvider), now);

    expect(notifier().takeRequest(), isTrue);
    expect(container.read(audioImportPickRequestProvider), isNull);
    expect(notifier().takeRequest(), isFalse);
  });

  test('a request is still taken just under 60 seconds after it was made', () {
    notifier().request();
    now = now.add(const Duration(seconds: 59, milliseconds: 999));
    expect(notifier().takeRequest(), isTrue);
  });

  test('a request older than 60 seconds is dropped, not taken', () {
    notifier().request();
    now = now.add(const Duration(seconds: 61));

    expect(notifier().takeRequest(), isFalse);
    expect(container.read(audioImportPickRequestProvider), isNull);
  });

  test('the pending flag clears at 60 seconds without any rebuild', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = <bool>[];
      container.listen(
        audioImportRequestPendingProvider,
        (_, pending) => seen.add(pending),
      );

      container.read(audioImportPickRequestProvider.notifier).request();
      expect(container.read(audioImportRequestPendingProvider), isTrue);

      async.elapse(const Duration(seconds: 59));
      expect(container.read(audioImportRequestPendingProvider), isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(container.read(audioImportRequestPendingProvider), isFalse);
      expect(seen, [true, false], reason: 'the listener must see the expiry');
    });
  });

  test('a new request restarts the 60 second lifetime', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final requests = container.read(audioImportPickRequestProvider.notifier);

      requests.request();
      async.elapse(const Duration(seconds: 50));
      requests.request();
      async.elapse(const Duration(seconds: 50));

      expect(container.read(audioImportRequestPendingProvider), isTrue);
    });
  });
}
