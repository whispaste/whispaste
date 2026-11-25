/// Overlay F (#194): "Eine Stunde ausblenden", "Overlay ausschalten", the
/// tray's way back and the capture-exclusion handoff.
///
/// Logic: the hide hour ends by the clock, errors and cards still show, and
/// "wieder einblenden" ends it. Handoffs: the context-menu actions `hide_hour`
/// and `turn_off`, and `setCaptureExcluded` on a switch change.
library;

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_overlay/overlay_hide_rules.dart';
import 'package:whispaste/services/tray_service.dart' show trayOverlayRestore;

class _FakeController
    implements FloatingOverlayController, OverlayCaptureExclusion {
  final _events = StreamController<FloatingOverlayEvent>.broadcast();
  final snapshots = <FloatingOverlaySnapshot>[];
  final captureCalls = <bool>[];
  List<Map<String, Object?>> menu = const [];

  FloatingOverlaySnapshot? get last =>
      snapshots.isEmpty ? null : snapshots.last;

  void emit(FloatingOverlayEvent e) => _events.add(e);

  @override
  Stream<FloatingOverlayEvent> get events => _events.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async =>
      snapshots.add(snapshot);

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode a) async {}

  @override
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) async => menu = items;

  @override
  Future<void> setCaptureExcluded(bool excluded) async =>
      captureCalls.add(excluded);

  @override
  Future<void> dispose() => _events.close();
}

class _Service extends FloatingOverlayService {
  _Service(this._fake, {required super.now});
  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? const AppSettings()));
  }
}

class _MicOpen extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus(
    captureState: AudioCaptureState.recording,
    hasLiveSamples: true,
  );
}

final _epoch = DateTime(2026, 11, 23, 14, 5);

({_FakeController fake, ProviderContainer c}) _build(FakeAsync async) {
  final fake = _FakeController();
  DateTime now() => _epoch.add(async.elapsed);
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_Settings.new),
      audioServiceProvider.overrideWith(_MicOpen.new),
      overlayHideClockProvider.overrideWithValue(now),
      floatingOverlayServiceProvider.overrideWith(
        () => _Service(fake, now: now),
      ),
    ],
  );
  c.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return (fake: fake, c: c);
}

void _step(FakeAsync async) {
  async.elapse(const Duration(milliseconds: 5));
  async.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('overlayFrameHeldBack', () {
    final until = _epoch.add(kOverlayHideDuration);

    bool heldBack({
      DateTime? hiddenUntil,
      DateTime? now,
      bool hasNotice = false,
      bool isError = false,
      bool guidance = false,
    }) => overlayFrameHeldBack(
      hiddenUntil: hiddenUntil,
      now: now ?? _epoch,
      hasNotice: hasNotice,
      isError: isError,
      guidance: guidance,
    );

    test('holds back a plain pill frame only while the hour runs', () {
      expect(heldBack(), isFalse);
      expect(heldBack(hiddenUntil: until), isTrue);
      expect(heldBack(hiddenUntil: until, now: until.subtract(_ms)), isTrue);
      expect(heldBack(hiddenUntil: until, now: until), isFalse);
    });

    test('errors, notice cards and guidance still show', () {
      expect(heldBack(hiddenUntil: until, isError: true), isFalse);
      expect(heldBack(hiddenUntil: until, hasNotice: true), isFalse);
      expect(heldBack(hiddenUntil: until, guidance: true), isFalse);
    });
  });

  group('OverlayHiddenUntilNotifier', () {
    test('ends by itself after one hour; showAgain ends it at once', () {
      FakeAsync().run((async) {
        final c = ProviderContainer(
          overrides: [
            overlayHideClockProvider.overrideWithValue(
              () => _epoch.add(async.elapsed),
            ),
          ],
        );
        addTearDown(c.dispose);
        final n = c.read(overlayHiddenUntilProvider.notifier);

        n.hideForAnHour();
        expect(
          c.read(overlayHiddenUntilProvider),
          _epoch.add(kOverlayHideDuration),
        );
        expect(n.hidesAt(), isTrue);

        async.elapse(kOverlayHideDuration - _ms);
        expect(n.hidesAt(), isTrue);
        async.elapse(_ms);
        expect(c.read(overlayHiddenUntilProvider), isNull);
        expect(n.hidesAt(), isFalse);

        n.hideForAnHour();
        n.showAgain();
        expect(c.read(overlayHiddenUntilProvider), isNull);
        // The cancelled timer of the first hour must not clear a new one.
        n.hideForAnHour();
        async.elapse(const Duration(minutes: 30));
        expect(n.hidesAt(), isTrue);
      });
    });
  });

  group('FloatingOverlayService — hide rules', () {
    test('hide_hour hides the pill and leaves the overlay mode on', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          final rec = h.c.read(recordingProvider.notifier);
          rec.startRecording();
          _step(async);
          expect(h.fake.last?.visible, isTrue);

          h.fake.emit(const OverlayContextMenuAction(overlayMenuHideHour));
          _step(async);

          expect(h.c.read(overlayHiddenUntilProvider), isNotNull);
          expect(
            h.c.read(settingsProvider).value!.effectiveOverlayMode,
            OverlayMode.floating,
          );
          expect(h.fake.last?.visible, isFalse);

          // The recording goes on; its ticks keep the pill away.
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();
          expect(h.fake.last?.visible, isFalse);

          // An error still shows.
          rec.fail('boom');
          _step(async);
          expect(h.fake.last?.visible, isTrue);
          expect(h.fake.last?.state, OverlayVisualState.error);
        } finally {
          h.c.dispose();
        }
      });
    });

    test('the pill is back once the hour is over or shown again', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          final rec = h.c.read(recordingProvider.notifier);
          h.c.read(overlayHiddenUntilProvider.notifier).hideForAnHour();
          rec.startRecording();
          _step(async);
          expect(h.fake.last?.visible, isFalse);

          h.c.read(overlayHiddenUntilProvider.notifier).showAgain();
          _step(async);
          expect(h.fake.last?.visible, isTrue);

          rec.reset();
          _step(async);
          h.c.read(overlayHiddenUntilProvider.notifier).hideForAnHour();
          async.elapse(kOverlayHideDuration);
          async.flushMicrotasks();
          rec.startRecording();
          _step(async);
          expect(h.fake.last?.visible, isTrue);
        } finally {
          h.c.dispose();
        }
      });
    });

    test('turn_off switches the overlay off', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          final ids = [for (final item in h.fake.menu) item['id']];
          expect(ids, containsAll([overlayMenuHideHour, overlayMenuTurnOff]));

          h.fake.emit(const OverlayContextMenuAction(overlayMenuTurnOff));
          _step(async);

          expect(
            h.c.read(settingsProvider).value!.effectiveOverlayMode,
            OverlayMode.off,
          );
          expect(h.c.read(overlayHiddenUntilProvider), isNull);
        } finally {
          h.c.dispose();
        }
      });
    });

    test('setCaptureExcluded follows the switch, once per change', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          expect(h.fake.captureCalls, [false]);
          final settings = h.c.read(settingsProvider.notifier);

          settings.updateSettings(
            (s) => s.copyWith(overlayHideFromCapture: true),
          );
          _step(async);
          settings.updateSettings((s) => s.copyWith(overlaySize: 'normal'));
          _step(async);
          settings.updateSettings(
            (s) => s.copyWith(overlayHideFromCapture: false),
          );
          _step(async);

          expect(h.fake.captureCalls, [false, true, false]);
        } finally {
          h.c.dispose();
        }
      });
    });
  });

  group('tray way back', () {
    setUpAll(() => initializeDateFormatting('de'));
    final l = lookupL10n(const Locale('de'));
    final until = DateTime(2026, 11, 23, 15, 5);

    test('names the end of the hour while it runs', () {
      final entry = trayOverlayRestore(
        l,
        overlayOn: true,
        hiddenUntil: until,
        now: _epoch,
      );
      expect(entry?.id, TrayCommandIds.overlayShowAgain);
      expect(entry?.label, contains('15:05'));
    });

    test('offers to turn the overlay on while it is off', () {
      final entry = trayOverlayRestore(
        l,
        overlayOn: false,
        hiddenUntil: null,
        now: _epoch,
      );
      expect(entry?.id, TrayCommandIds.overlayTurnOn);
    });

    test('is absent while the overlay shows normally', () {
      expect(
        trayOverlayRestore(l, overlayOn: true, hiddenUntil: null, now: _epoch),
        isNull,
      );
      expect(
        trayOverlayRestore(l, overlayOn: true, hiddenUntil: until, now: until),
        isNull,
      );
    });

    test('the entry lands in the tray tree', () {
      final tree = buildTrayCommands(
        const TrayMenuState(
          isRecording: false,
          micDeviceLabels: [],
          selectedMic: '',
          overlayRestore: (id: TrayCommandIds.overlayTurnOn, label: 'x'),
        ),
        const {},
      );
      expect(tree.map((c) => c.id), contains(TrayCommandIds.overlayTurnOn));
    });
  });

  test('capture exclusion is offered on macOS and Windows only', () {
    expect(overlayCaptureExclusionApplies(TargetPlatform.macOS), isTrue);
    expect(overlayCaptureExclusionApplies(TargetPlatform.windows), isTrue);
    expect(overlayCaptureExclusionApplies(TargetPlatform.linux), isFalse);
  });
}

const _ms = Duration(milliseconds: 1);
