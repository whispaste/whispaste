/// Focused UX harness for bundle 1a (honest states and conflict warnings):
/// the recording dock's done state "In der Zwischenablage" (neutral dot) next
/// to the pasted state as a baseline, and the dictation trigger dialog with the
/// macOS Fn double-tap conflict (two next steps) and with the Linux Wayland
/// hint. Survey tool, asserts nothing: layout exceptions go to exceptions.log,
/// PNGs to the output dir. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_1a_states_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/services/paste/paster.dart' show PasteOutcome;
import 'package:whispaste/widgets/recording_behavior.dart'
    show showPasteFailureToast;
import 'package:whispaste/widgets/recording_dock.dart';

import '../../test/features/settings/widgets/settings_golden_board.dart'
    show kSettingsGoldenSets;
import '../../test/fixtures/dock_choice_fixtures.dart';
import '../../test/fixtures/test_helpers.dart';
import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 1.3, 2.0];
const List<String> _themes = ['dark', 'navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// Dock done states: neutral unconfirmed (1a) and the confirmed paste.
enum _DoneState { unconfirmed, pasted }

WpRecordingDock _doneDock(L10n l10n, _DoneState state) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  engine: dockTestEngine(
    label: 'Whisper · small',
    overline: l10n.settingsSttEngine,
  ),
  sttState: SttServerState.ready,
  smartMode: dockTestSmartMode(label: 'Aus', overline: l10n.navSmartMode),
  hotkeyLabel: 'Strg+Umschalt+D',
  onHotkeyTap: () {},
  microphoneLabel: micDefaultLabel,
  microphoneOptions: const [micDefaultLabel, 'USB-Mikrofon'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Kopieren',
  afterAction: AfterTranscriptionAction.clipboard,
  onAfterActionChanged: (_) {},
  language: dockTestLanguage(label: 'DE', overline: l10n.settingsLanguage),
  onSttTap: () {},
  backendKind: 'GPU',
  backendUtilizationPercent: 2,
  onSupportTap: () {},
  recordingPhase: RecordingPhase.done,
  doneMessage: state == _DoneState.unconfirmed
      ? l10n.overlayDoneInClipboard
      : l10n.overlayDonePasted,
  doneUnconfirmed: state == _DoneState.unconfirmed,
);

Future<void> _capture(WidgetTester tester, String outDir, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  Directory(outDir).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey(kUxCaptureKey)),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _logLine(String outDir, String file, String line) {
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$file').writeAsStringSync('$line\n', mode: FileMode.append);
}

Future<void> _pumpDone(
  WidgetTester tester,
  HistoryDatabase db,
  Size size,
  double scale,
  String theme,
  String locale,
  _DoneState state,
) async {
  final set = kSettingsGoldenSets[theme]!;
  WpColors.activate(set);
  addTearDown(() => WpColors.activate(kSettingsGoldenSets['dark']!));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      Theme(
        data: wpThemeFor(set),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const ValueKey(kUxCaptureKey),
              child: ColoredBox(
                color: set.background,
                child: SizedBox.expand(
                  child: Navigator(
                    onGenerateRoute: (_) => PageRouteBuilder<void>(
                      pageBuilder: (routeContext, _, _) => Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: size.width,
                          child: _doneDock(L10n.of(routeContext), state),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      size: size,
      locale: Locale(locale),
      db: db,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Hosts a Navigator inside the capture boundary and opens the trigger dialog
/// on the first frame, so the dialog route is part of the PNG.
class _TriggerProbe extends StatefulWidget {
  const _TriggerProbe({required this.isWayland});

  final bool isWayland;

  @override
  State<_TriggerProbe> createState() => _TriggerProbeState();
}

class _TriggerProbeState extends State<_TriggerProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        WpHotkeyRecorderDialog.show(
          context,
          initialKey: 'D',
          initialModifiers: 'meta+shift',
          isWayland: widget.isWayland,
          singleKeys: widget.isWayland
              ? const {}
              : ModifierHotkey.values.toSet(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _pumpTrigger(
  WidgetTester tester,
  HistoryDatabase db,
  Size size,
  double scale,
  String locale, {
  required bool isWayland,
}) async {
  await pumpUxScreen(
    tester,
    screen: UxScreen(
      id: 'trigger-1a',
      activePageId: 'settings',
      build: () => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => _TriggerProbe(isWayland: isWayland),
        ),
      ),
    ),
    db: db,
    size: size,
    scale: scale,
    theme: 'navy',
    locale: locale,
  );
}

/// Shows the unconfirmed-paste toast once the first frame is on screen. The
/// toast goes into the nearest Overlay, so the probe hosts one (as the toast
/// harness does). On the mac test host the macOS password/PIN sentence is set.
class _ToastProbe extends StatelessWidget {
  const _ToastProbe();

  @override
  Widget build(BuildContext context) =>
      Overlay(initialEntries: [OverlayEntry(builder: _entry)]);

  static Widget _entry(BuildContext context) => const _ToastTrigger();
}

class _ToastTrigger extends StatefulWidget {
  const _ToastTrigger();

  @override
  State<_ToastTrigger> createState() => _ToastTriggerState();
}

class _ToastTriggerState extends State<_ToastTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPasteFailureToast(
        context: context,
        l10n: L10n.of(context),
        outcome: PasteOutcome.unconfirmed,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final state in _DoneState.values) {
    for (final size in _sizes) {
      for (final scale in _scales) {
        for (final theme in _themes) {
          for (final locale in _locales) {
            final name =
                '1a-dock-done-${state.name}'
                '__${size.width.toInt()}x${size.height.toInt()}'
                '__s${scale.toString()}__${theme}_$locale';
            testWidgets('ux-1a: $name', (tester) async {
              final db = await openSeededUxDatabase(tester);
              addTearDown(() => tester.runAsync(db.close));
              await _pumpDone(tester, db, size, scale, theme, locale, state);
              await _capture(tester, outDir, name);
              final error = tester.takeException();
              if (error != null) {
                _logLine(outDir, 'exceptions.log', '$name: $error');
              }
              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 1));
            });
          }
        }
      }
    }
  }

  // Unconfirmed-paste toast with the macOS password/PIN sentence (1a).
  for (final size in _sizes) {
    for (final scale in [1.0, 2.0]) {
      for (final locale in _locales) {
        final name =
            '1a-toast-unconfirmed'
            '__${size.width.toInt()}x${size.height.toInt()}'
            '__s${scale.toString()}__navy_$locale';
        testWidgets('ux-1a: $name', (tester) async {
          final db = await openSeededUxDatabase(tester);
          addTearDown(() => tester.runAsync(db.close));
          await pumpUxScreen(
            tester,
            screen: const UxScreen(
              id: 'toast-1a',
              activePageId: 'settings',
              build: _ToastProbe.new,
            ),
            db: db,
            size: size,
            scale: scale,
            theme: 'navy',
            locale: locale,
          );
          await _capture(tester, outDir, name);
          final error = tester.takeException();
          if (error != null) {
            _logLine(outDir, 'exceptions.log', '$name: $error');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }

  // Trigger dialog: macOS Fn double tap (a conflict with system dictation,
  // two next steps) and the Linux Wayland hint (desktop sets the shortcut).
  for (final isWayland in [false, true]) {
    final variant = isWayland ? 'wayland' : 'fn-conflict';
    for (final size in _sizes) {
      for (final scale in [1.0, 2.0]) {
        for (final locale in _locales) {
          final name =
              '1a-trigger-$variant'
              '__${size.width.toInt()}x${size.height.toInt()}'
              '__s${scale.toString()}__navy_$locale';
          testWidgets('ux-1a: $name', (tester) async {
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));
            await _pumpTrigger(
              tester,
              db,
              size,
              scale,
              locale,
              isWayland: isWayland,
            );
            await tester.pump(const Duration(milliseconds: 600));
            if (!isWayland) {
              final fn = find.text('Fn (nur macOS)');
              if (fn.evaluate().isEmpty) {
                _logLine(outDir, 'exceptions.log', '$name: Fn chip not found');
              } else {
                await tester.tap(fn.first);
              }
            }
            await _capture(tester, outDir, name);
            final error = tester.takeException();
            if (error != null) {
              _logLine(outDir, 'exceptions.log', '$name: $error');
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
          });
        }
      }
    }
  }
}
