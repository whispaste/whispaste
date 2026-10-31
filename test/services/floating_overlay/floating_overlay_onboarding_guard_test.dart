/// The native overlay stays out of the onboarding surface (V11-10, MP-3).
///
/// A hotkey press refused with `onboarding_not_completed` while onboarding is
/// on screen must not reach the floating overlay as an error. The control case
/// shows that the same error still reaches it once onboarding is over.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/snippets/interactive_snippet_controller.dart';

class _FakeController implements FloatingOverlayController {
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  FloatingOverlaySnapshot? lastSnapshot;

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    lastSnapshot = snapshot;
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(
    double x,
    double y,
    OverlayAnchorMode anchor,
  ) async {}

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {}

  @override
  Future<void> dispose() async {
    await _eventCtrl.close();
  }
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});
  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

class _Harness {
  _Harness(this.fake, this.container);
  final _FakeController fake;
  final ProviderContainer container;

  void dispose() => container.dispose();
}

_Harness _build(FakeAsync async, {required bool onboardingCompleted}) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _FakeController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _FixedSettingsNotifier(
          AppSettings(
            onboarding: OnboardingSettings(
              onboardingCompleted: onboardingCompleted,
            ),
          ),
        ),
      ),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
      interactiveSnippetControllerProvider.overrideWith(
        InteractiveSnippetController.new,
      ),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return _Harness(fake, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a hotkey refusal during onboarding never reaches the overlay as an '
      'error', () {
    FakeAsync().run((async) {
      final h = _build(async, onboardingCompleted: false);
      addTearDown(h.dispose);
      final before = h.fake.lastSnapshot;

      h.container
          .read(recordingProvider.notifier)
          .fail('onboarding_not_completed');
      // Riverpod delivers the derived phase on a scheduler timer.
      async.elapse(const Duration(milliseconds: 1));

      expect(identical(h.fake.lastSnapshot, before), isTrue);
      expect(h.fake.lastSnapshot?.state, isNot(OverlayVisualState.error));
    });
  });

  test('the same error after onboarding still reaches the overlay', () {
    FakeAsync().run((async) {
      final h = _build(async, onboardingCompleted: true);
      addTearDown(h.dispose);

      h.container
          .read(recordingProvider.notifier)
          .fail('onboarding_not_completed');
      // Riverpod delivers the derived phase on a scheduler timer.
      async.elapse(const Duration(milliseconds: 1));

      expect(h.fake.lastSnapshot?.state, OverlayVisualState.error);
    });
  });
}
