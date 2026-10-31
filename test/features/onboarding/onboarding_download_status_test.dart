import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_download_status.dart';
import 'package:whispaste/services/model_download_service.dart'
    show DownloadPhase;
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart'
    show ParakeetDownloadPhase;

const _mb = 1000000;

void main() {
  group('DownloadThroughput', () {
    test('gives no estimate before two samples', () {
      final t = DownloadThroughput();
      expect(t.remainingFor(10 * _mb), isNull);
      t.record(Duration.zero, 0);
      expect(t.bytesPerSecond, isNull);
    });

    test('gives no estimate before the minimum span of 3 s', () {
      final t = DownloadThroughput();
      t.record(Duration.zero, 0);
      t.record(const Duration(seconds: 2), 2 * _mb);
      expect(t.bytesPerSecond, isNull);
      expect(t.remainingFor(10 * _mb), isNull);
    });

    test('estimates the time left from a stable rate', () {
      final t = DownloadThroughput();
      for (var s = 0; s <= 5; s++) {
        t.record(Duration(seconds: s), s * _mb);
      }
      expect(t.bytesPerSecond, closeTo(_mb.toDouble(), 1));
      final eta = t.remainingFor(5 * _mb);
      expect(eta, isNotNull);
      expect(eta!.inMilliseconds, closeTo(5000, 5));
    });

    test('gives no estimate while the rate is unstable', () {
      // First half 1 MB/s, second half 10 MB/s: outside the 1.6 factor.
      final t = DownloadThroughput();
      const bytes = [0, 1, 2, 3, 13, 23];
      for (var s = 0; s < bytes.length; s++) {
        t.record(Duration(seconds: s), bytes[s] * _mb);
      }
      expect(t.bytesPerSecond, isNull);
      expect(t.remainingFor(10 * _mb), isNull);
    });

    test('ignores samples that go back in time or in bytes', () {
      final t = DownloadThroughput();
      t.record(Duration.zero, 0);
      t.record(const Duration(seconds: 4), 4 * _mb);
      t.record(const Duration(seconds: 2), 9 * _mb);
      t.record(const Duration(seconds: 5), 1 * _mb);
      t.record(const Duration(seconds: 6), 6 * _mb);
      expect(t.bytesPerSecond, closeTo(_mb.toDouble(), 1));
    });

    test('returns null when nothing is left', () {
      final t = DownloadThroughput();
      for (var s = 0; s <= 5; s++) {
        t.record(Duration(seconds: s), s * _mb);
      }
      expect(t.remainingFor(0), isNull);
    });

    test('uses only the recent window', () {
      // A slow start, then a steady 4 MB/s well inside the 10 s window.
      final t = DownloadThroughput();
      t.record(Duration.zero, 0);
      t.record(const Duration(seconds: 20), 1 * _mb);
      for (var s = 21; s <= 30; s++) {
        t.record(Duration(seconds: s), (1 + (s - 20) * 4) * _mb);
      }
      expect(t.bytesPerSecond, closeTo(4 * _mb.toDouble(), 1));
    });
  });

  group('onboardingStatusFromWhisper', () {
    test('an installed model that is idle counts as ready', () {
      final s = onboardingStatusFromWhisper(
        phase: DownloadPhase.idle,
        bytesDone: 0,
        bytesTotal: 0,
        installed: true,
      );
      expect(s.phase, OnboardingDownloadPhase.ready);
      expect(s.practiceUnlocked, isTrue);
    });

    test('a missing model that is idle is not ready', () {
      final s = onboardingStatusFromWhisper(
        phase: DownloadPhase.idle,
        bytesDone: 0,
        bytesTotal: 0,
        installed: false,
      );
      expect(s.phase, OnboardingDownloadPhase.idle);
      expect(s.practiceUnlocked, isFalse);
    });

    test('a running download keeps practice locked and shows the ETA', () {
      final s = onboardingStatusFromWhisper(
        phase: DownloadPhase.downloading,
        bytesDone: 25 * _mb,
        bytesTotal: 100 * _mb,
        installed: false,
        remaining: const Duration(seconds: 90),
      );
      expect(s.phase, OnboardingDownloadPhase.running);
      expect(s.practiceUnlocked, isFalse);
      expect(s.fraction, closeTo(0.25, 1e-9));
      expect(s.remaining, const Duration(seconds: 90));
    });

    test('an error is failed and carries no ETA', () {
      final s = onboardingStatusFromWhisper(
        phase: DownloadPhase.error,
        bytesDone: 40 * _mb,
        bytesTotal: 100 * _mb,
        installed: false,
        remaining: const Duration(seconds: 90),
      );
      expect(s.phase, OnboardingDownloadPhase.failed);
      expect(s.practiceUnlocked, isFalse);
      expect(s.remaining, isNull);
      expect(s.bytesDone, 40 * _mb, reason: 'kept parts stay visible');
    });

    test('done is ready, verifying is not', () {
      expect(
        onboardingStatusFromWhisper(
          phase: DownloadPhase.done,
          bytesDone: 0,
          bytesTotal: 0,
          installed: true,
        ).practiceUnlocked,
        isTrue,
      );
      expect(
        onboardingStatusFromWhisper(
          phase: DownloadPhase.verifying,
          bytesDone: 0,
          bytesTotal: 0,
          installed: false,
        ).practiceUnlocked,
        isFalse,
      );
    });
  });

  group('onboardingStatusFromParakeet', () {
    test('maps the phases to the same footer states', () {
      OnboardingDownloadStatus map(ParakeetDownloadPhase p) =>
          onboardingStatusFromParakeet(
            phase: p,
            bytesDone: 0,
            bytesTotal: 0,
            installed: false,
          );
      expect(
        map(ParakeetDownloadPhase.downloading).phase,
        OnboardingDownloadPhase.running,
      );
      expect(
        map(ParakeetDownloadPhase.verifying).phase,
        OnboardingDownloadPhase.verifying,
      );
      expect(
        map(ParakeetDownloadPhase.done).phase,
        OnboardingDownloadPhase.ready,
      );
      expect(
        map(ParakeetDownloadPhase.error).phase,
        OnboardingDownloadPhase.failed,
      );
      expect(
        map(ParakeetDownloadPhase.idle).phase,
        OnboardingDownloadPhase.idle,
      );
    });
  });

  test('fraction is zero while the total is unknown', () {
    const s = OnboardingDownloadStatus(
      phase: OnboardingDownloadPhase.running,
      bytesDone: 5 * _mb,
    );
    expect(s.fraction, 0);
  });

  group('practice gate (the try-out lock)', () {
    OnboardingDownloadStatus of(OnboardingDownloadPhase phase) =>
        OnboardingDownloadStatus(phase: phase);

    test('a local engine is open only once its model is ready', () {
      expect(
        practiceGateFor(
          localEngine: true,
          status: of(OnboardingDownloadPhase.ready),
        ),
        PracticeGate.open,
      );
      expect(
        practiceGateFor(
          localEngine: true,
          status: of(OnboardingDownloadPhase.running),
        ),
        PracticeGate.loading,
      );
      expect(
        practiceGateFor(
          localEngine: true,
          status: of(OnboardingDownloadPhase.verifying),
        ),
        PracticeGate.loading,
      );
      expect(
        practiceGateFor(
          localEngine: true,
          status: of(OnboardingDownloadPhase.failed),
        ),
        PracticeGate.failed,
      );
      expect(
        practiceGateFor(
          localEngine: true,
          status: of(OnboardingDownloadPhase.idle),
        ),
        PracticeGate.missing,
      );
    });

    test(
      'a cloud provider is never locked, whatever the local download is',
      () {
        for (final phase in OnboardingDownloadPhase.values) {
          expect(
            practiceGateFor(localEngine: false, status: of(phase)),
            PracticeGate.open,
            reason: 'cloud needs no local model ($phase)',
          );
        }
      },
    );
  });
}
