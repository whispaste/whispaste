/// #877: a download started from a card reports its progress at the pill.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/download_pill_progress.dart';
import 'package:whispaste/services/floating_overlay/pill_hint.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

class _FakeWhisper extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();

  void set(ModelDownloadState s) => state = s;
}

class _FakeParakeet extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();

  void set(ParakeetDownloadState s) => state = s;
}

void main() {
  late ProviderContainer c;
  final shown = <String>[];

  setUp(() {
    shown.clear();
    c = ProviderContainer(
      overrides: [
        modelDownloadProvider.overrideWith(_FakeWhisper.new),
        parakeetDownloadProvider.overrideWith(_FakeParakeet.new),
      ],
    );
    c.listen<OverlayPillHint?>(overlayPillHintProvider, (_, h) {
      if (h != null) shown.add(h.text);
    });
  });
  tearDown(() => c.dispose());

  _FakeWhisper whisper() =>
      c.read(modelDownloadProvider.notifier) as _FakeWhisper;
  _FakeParakeet parakeet() =>
      c.read(parakeetDownloadProvider.notifier) as _FakeParakeet;

  void follow() => c
      .read(downloadPillProgressProvider.notifier)
      .follow(progressText: (p) => 'dl $p', readyText: 'ready');

  ModelDownloadState w(DownloadPhase phase, [int p = 0]) =>
      ModelDownloadState(phase: phase, progressPercent: p);

  test('each new percent of the followed download reaches the pill', () {
    follow();
    for (final p in [0, 0, 7, 7, 42, 100]) {
      whisper().set(w(DownloadPhase.downloading, p));
    }
    whisper().set(w(DownloadPhase.done, 100));
    expect(shown, ['dl 0', 'dl 7', 'dl 42', 'dl 100', 'ready']);
    expect(c.read(downloadPillProgressProvider), isNull);
  });

  test('the Parakeet bundle is followed the same way', () {
    follow();
    parakeet().set(
      const ParakeetDownloadState(
        phase: ParakeetDownloadPhase.downloading,
        progressPercent: 30,
      ),
    );
    parakeet().set(
      const ParakeetDownloadState(phase: ParakeetDownloadPhase.done),
    );
    expect(shown, ['dl 30', 'ready']);
  });

  test('a failed download ends quietly, without "ready"', () {
    follow();
    whisper().set(w(DownloadPhase.downloading, 12));
    whisper().set(w(DownloadPhase.error));
    expect(shown, ['dl 12']);
    expect(c.read(downloadPillProgressProvider), isNull);
  });

  test('a download nobody started from a card stays off the pill', () {
    c.read(downloadPillProgressProvider);
    whisper().set(w(DownloadPhase.downloading, 50));
    whisper().set(w(DownloadPhase.done, 100));
    expect(shown, isEmpty);
  });

  test('after the end, a later download is not followed again', () {
    follow();
    whisper().set(w(DownloadPhase.downloading, 5));
    whisper().set(w(DownloadPhase.done, 100));
    shown.clear();
    whisper().set(w(DownloadPhase.downloading, 60));
    expect(shown, isEmpty);
  });
}
