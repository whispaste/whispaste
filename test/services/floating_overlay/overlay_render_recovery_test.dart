import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_recovery.dart';

/// Fake-clock tests for the render-engine frame heartbeat policy (WP-84 phase 2,
/// plan item 1). The machine is pure: every instant is passed in explicitly.
void main() {
  final t0 = DateTime(2026, 10, 18, 12);
  const deadline = Duration(milliseconds: 500);

  RenderRecoveryMachine machine({int budget = 3}) =>
      RenderRecoveryMachine(frameDeadline: deadline, sessionBudget: budget);

  group('RenderRecoveryMachine', () {
    test('a frame before the deadline ends the episode without action', () {
      final m = machine();
      m.onShown(t0);
      m.onFrame();

      expect(
        m.onDeadline(t0.add(const Duration(seconds: 5))),
        RenderRecoveryAction.none,
      );
      expect(m.reboots, 0);
      expect(m.armed, isFalse);
    });

    test('no frame by the deadline yields exactly one reboot', () {
      final m = machine();
      m.onShown(t0);

      expect(
        m.onDeadline(t0.add(deadline - const Duration(milliseconds: 1))),
        RenderRecoveryAction.none,
        reason: 'the deadline is not reached one millisecond early',
      );
      expect(m.onDeadline(t0.add(deadline)), RenderRecoveryAction.reboot);
      expect(m.reboots, 1);
    });

    test('after a reboot the new engine gets a fresh deadline', () {
      final m = machine();
      m.onShown(t0);
      final rebootAt = t0.add(deadline);
      expect(m.onDeadline(rebootAt), RenderRecoveryAction.reboot);

      expect(
        m.onDeadline(rebootAt.add(deadline - const Duration(milliseconds: 1))),
        RenderRecoveryAction.none,
      );
      m.onFrame();
      expect(
        m.onDeadline(rebootAt.add(const Duration(seconds: 10))),
        RenderRecoveryAction.none,
      );
      expect(m.reboots, 1, reason: 'a healthy re-boot is exactly one reboot');
    });

    test('a second show does not restart a running deadline', () {
      final m = machine();
      m.onShown(t0);
      m.onShown(t0.add(const Duration(milliseconds: 300)));

      expect(m.deadline, t0.add(deadline));
    });

    test('hiding disarms: a hidden shell is never rebooted', () {
      final m = machine();
      m.onShown(t0);
      m.onHidden();

      expect(
        m.onDeadline(t0.add(const Duration(seconds: 5))),
        RenderRecoveryAction.none,
      );
      expect(m.reboots, 0);
    });

    test('the session budget caps reboots and reports exhaustion once', () {
      final m = machine(budget: 2);
      var now = t0;
      m.onShown(now);

      now = now.add(deadline);
      expect(m.onDeadline(now), RenderRecoveryAction.reboot);
      now = now.add(deadline);
      expect(m.onDeadline(now), RenderRecoveryAction.reboot);
      now = now.add(deadline);
      expect(m.onDeadline(now), RenderRecoveryAction.budgetExhausted);

      m.onShown(now);
      now = now.add(deadline);
      expect(
        m.onDeadline(now),
        RenderRecoveryAction.none,
        reason: 'the exhaustion is logged once per session, not per show',
      );
      expect(m.reboots, 2);
    });

    test('neither a frame nor a new show restores the budget', () {
      final m = machine(budget: 1);
      m.onShown(t0);
      m.onDeadline(t0.add(deadline)); // the only allowed reboot
      m.onFrame();
      m.onHidden();

      final later = t0.add(const Duration(minutes: 1));
      m.onShown(later);
      expect(
        m.onDeadline(later.add(deadline)),
        RenderRecoveryAction.budgetExhausted,
      );
      expect(m.reboots, 1);
    });

    test('a frame with no armed deadline is a no-op', () {
      final m = machine();
      m.onFrame();

      expect(m.armed, isFalse);
      expect(m.deadline, isNull);
    });
  });

  group('RenderRecoveryMachine with repushBeforeReboot', () {
    RenderRecoveryMachine repushing({int budget = 3}) => RenderRecoveryMachine(
      frameDeadline: deadline,
      sessionBudget: budget,
      repushBeforeReboot: true,
    );

    test('the first missed deadline of an episode asks for a re-push only', () {
      final m = repushing();
      m.onShown(t0);

      expect(m.onDeadline(t0.add(deadline)), RenderRecoveryAction.repush);
      expect(m.reboots, 0, reason: 'a re-push spends no re-boot');
      expect(m.stalled, isTrue);
      expect(
        m.deadline,
        t0.add(deadline * 2),
        reason: 'the re-push gets its own full deadline',
      );
    });

    test('a missed deadline after the re-push requests the re-boot', () {
      final m = repushing();
      m.onShown(t0);
      m.onDeadline(t0.add(deadline));

      expect(m.onDeadline(t0.add(deadline * 2)), RenderRecoveryAction.reboot);
      expect(m.reboots, 1);
    });

    test('a frame after the re-push ends the episode without a re-boot', () {
      final m = repushing();
      m.onShown(t0);
      m.onDeadline(t0.add(deadline));
      m.onFrame();

      expect(m.stalled, isFalse);
      expect(
        m.onDeadline(t0.add(const Duration(seconds: 10))),
        RenderRecoveryAction.none,
      );
      expect(m.reboots, 0);
    });

    test('the next episode starts again with a re-push', () {
      final m = repushing();
      m.onShown(t0);
      m.onDeadline(t0.add(deadline));
      m.onFrame();
      m.onHidden();

      final later = t0.add(const Duration(minutes: 1));
      m.onShown(later);
      expect(m.onDeadline(later.add(deadline)), RenderRecoveryAction.repush);
    });

    test('hiding during a stall clears it', () {
      final m = repushing();
      m.onShown(t0);
      m.onDeadline(t0.add(deadline));
      m.onHidden();

      expect(m.stalled, isFalse);
      expect(m.armed, isFalse);
    });

    test('the session budget still bounds the re-boots', () {
      final m = repushing(budget: 1);
      m.onShown(t0);
      m.onDeadline(t0.add(deadline)); // re-push
      m.onDeadline(t0.add(deadline * 2)); // the only allowed re-boot

      expect(
        m.onDeadline(t0.add(deadline * 3)),
        RenderRecoveryAction.budgetExhausted,
        reason: 'the episode already re-pushed; the spent budget ends it',
      );
      expect(m.reboots, 1);
    });

    test('a late deadline caused by a blocked UI thread does not reboot', () {
      final m = machine();
      m.onShown(t0);
      // The timer itself fired two seconds late: the Dart UI thread was
      // blocked, so the engine cannot be judged stuck.
      final late = t0.add(deadline + const Duration(seconds: 2));

      expect(
        m.onDeadline(late, lag: const Duration(seconds: 2)),
        RenderRecoveryAction.none,
      );
      expect(m.reboots, 0, reason: 'a blocked UI thread spends no budget');
      expect(m.armed, isTrue, reason: 'the deadline restarts from the stall');
      expect(
        m.onDeadline(late.add(deadline)),
        RenderRecoveryAction.reboot,
        reason: 'a genuinely silent engine is still rebooted afterwards',
      );
    });

    test('the first lazy boot of a session gets a grace period', () {
      final m = RenderRecoveryMachine(
        frameDeadline: deadline,
        sessionBudget: 3,
        firstEpisodeGrace: const Duration(seconds: 3),
      );
      m.onShown(t0);

      expect(
        m.onDeadline(t0.add(deadline)),
        RenderRecoveryAction.none,
        reason: 'the engine is still booting on its first show',
      );
      expect(
        m.onDeadline(t0.add(deadline + const Duration(seconds: 3))),
        RenderRecoveryAction.reboot,
      );
    });

    test('the grace is only for the first episode', () {
      final m = RenderRecoveryMachine(
        frameDeadline: deadline,
        sessionBudget: 3,
        firstEpisodeGrace: const Duration(seconds: 3),
      );
      m.onShown(t0);
      m.onFrame();
      m.onHidden();
      m.onShown(t0.add(const Duration(seconds: 10)));

      expect(
        m.onDeadline(t0.add(const Duration(seconds: 10)).add(deadline)),
        RenderRecoveryAction.reboot,
      );
    });
  });
}
