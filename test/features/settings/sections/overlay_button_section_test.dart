/// Round-trip widget tests for [OverlaySection] and [FloatingButtonSection].
///
/// Covers:
/// - OverlaySection: consolidated start-position dropdown (off = overlay
///   disabled; real position = overlay enabled). No separate show-overlay
///   toggle row.
/// - OverlaySection: real overlay preview (OverlayRealPreview / FloatingOverlayView)
///   inside the size row's trailing when enabled, absent when disabled.
/// - FloatingButtonSection: toggle round-trip (showFloatingButton false → true).
///   FloatingButtonView is always visible in the trailing of the toggle row.
///
/// Platform notes:
/// - OverlaySection renders on all desktop platforms (Windows / macOS / Linux).
/// - FloatingButtonSection renders only on Windows and macOS; tests for it
///   use a runtime platform guard instead of `skip` so they pass vacuously on
///   Linux CI rather than being counted as skipped.
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';
import 'package:whispaste/widgets/overlay_preview.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

// ---------------------------------------------------------------------------
// Platform guards (evaluated at runtime, not at compile time)
// ---------------------------------------------------------------------------

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  // OverlaySection
  // ══════════════════════════════════════════════════════════════════════════

  group('OverlaySection', () {
    testWidgets(
      'no Switch in OverlaySection; start-position dropdown always visible on desktop',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'off'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // The on/off toggle has been replaced by the start-position dropdown.
        expect(find.byType(Switch), findsNothing);

        if (_isDesktop) {
          // Start-position dropdown (with 'Aus' as first entry) always visible.
          expect(find.byType(DropdownButton<String>), findsOneWidget);
        } else {
          expect(find.byType(DropdownButton<String>), findsNothing);
        }
      },
    );

    testWidgets(
      'one dropdown visible when overlay is off (start position showing Aus)',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'off'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // Start-position dropdown is always visible on desktop; it shows
        // the 'Aus' (off) entry when the overlay is disabled.
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        // Size dropdown hidden — overlay is off.
        expect(find.byType(OverlayRealPreview), findsNothing);
      },
    );

    testWidgets(
      'switching overlayMode to floating reveals size + preview row',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'off'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // Initially: 1 dropdown, no size row.
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        expect(notifier.state.value!.overlay.overlayMode, 'off');

        // Simulate selecting a real start position → overlay enabled.
        notifier.updateSettings(
          (s) => s.copyWith(
            overlayMode: OverlayMode.floating.value,
            showOverlay: true,
            overlayStartPosition: OverlayStartPosition.topCenter.value,
          ),
        );
        await tester.pump();

        expect(
          notifier.state.value!.overlay.overlayMode,
          OverlayMode.floating.value,
        );
        expect(notifier.state.value!.overlay.showOverlay, isTrue);
        // Start-position + size dropdowns now both visible.
        expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      },
    );

    testWidgets(
      'nested overlay dropdowns appear when overlayMode is floating',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'floating'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        // FloatingOverlayView has an infinite AnimationController — use pump()
        // instead of pumpAndSettle() to avoid a timeout.
        await tester.pump();
        await tester.pump();

        // Floating mode reveals start-position + size dropdowns.
        expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      },
    );

    // -- AC (a) ---------------------------------------------------------------
    testWidgets(
      'selecting Aus via state sets overlayMode off, showOverlay false, '
      'hides size row',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'floating'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pump();
        await tester.pump();

        // Floating: 2 dropdowns visible.
        expect(find.byType(DropdownButton<String>), findsNWidgets(2));

        // Simulate 'Aus' selection callback.
        notifier.updateSettings(
          (s) => s.copyWith(
            overlayMode: OverlayMode.off.value,
            showOverlay: false,
          ),
        );
        await tester.pump();

        expect(notifier.state.value!.overlay.overlayMode, 'off');
        expect(notifier.state.value!.overlay.showOverlay, isFalse);
        // Only start-position dropdown remains; size row hidden.
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        expect(find.byType(OverlayRealPreview), findsNothing);
      },
    );

    // -- AC (b) ---------------------------------------------------------------
    testWidgets('selecting a position via state sets overlayMode floating, '
        'showOverlay true, reveals size row', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(overlayMode: 'off'),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String>), findsOneWidget);

      // Simulate selecting 'top-center' from the dropdown.
      notifier.updateSettings(
        (s) => s.copyWith(
          overlayMode: OverlayMode.floating.value,
          showOverlay: true,
          overlayStartPosition: OverlayStartPosition.topCenter.value,
        ),
      );
      await tester.pump();

      expect(
        notifier.state.value!.overlay.overlayMode,
        OverlayMode.floating.value,
      );
      expect(notifier.state.value!.overlay.showOverlay, isTrue);
      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    });

    // -- AC (c) ---------------------------------------------------------------
    testWidgets(
      'no separate show-overlay Switch exists in OverlaySection on desktop',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        // Even with overlay enabled, no Switch widget should appear.
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'floating'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(Switch), findsNothing);
      },
    );

    // -- AC (d) ---------------------------------------------------------------
    testWidgets(
      'OverlayRealPreview in size-row trailing: only one Divider when floating',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'floating'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pump();
        await tester.pump();

        // Preview is present …
        expect(find.byType(OverlayRealPreview), findsOneWidget);
        // … and has no standalone Divider before it: only one Divider separates
        // the start-position row from the size row (which contains the preview).
        expect(find.byType(Divider), findsOneWidget);
      },
    );

    // -- AC (e) ---------------------------------------------------------------
    testWidgets(
      'no RenderFlex overflow at 400 px narrow width with floating overlay',
      (tester) async {
        if (!_isDesktop) return; // Platform guard.

        final overflows = <String>[];
        final originalHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            originalHandler?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = originalHandler);

        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(overlayMode: 'floating'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: OverlaySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            size: const Size(400, 600),
          ),
        );
        // FloatingOverlayView has an infinite AnimationController — pump() only.
        await tester.pump();
        await tester.pump();

        expect(
          overflows,
          isEmpty,
          reason: 'RenderFlex overflow at 400 px:\n${overflows.join('\n')}',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // FloatingButtonSection
  // ══════════════════════════════════════════════════════════════════════════

  group('FloatingButtonSection', () {
    testWidgets(
      'renders on macOS / Windows (Switch visible), empty SizedBox on Linux',
      (tester) async {
        // FloatingButtonSection uses defaultTargetPlatform for branching, so
        // we use debugDefaultTargetPlatformOverride to exercise each branch.
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final notifier = _FakeSettingsNotifier(AppSettings.defaults);
          await tester.pumpWidget(
            makeTestable(
              const SingleChildScrollView(child: FloatingButtonSection()),
              overrides: [settingsProvider.overrideWith(() => notifier)],
            ),
          );
          await tester.pumpAndSettle();

          // Section should render with at least the toggle Switch on Windows.
          expect(find.byType(Switch), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'floating button toggle round-trip updates overlay.showFloatingButton',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final notifier = _FakeSettingsNotifier(
            AppSettings.defaults.copyWithSections(
              overlay: const OverlaySettings(showFloatingButton: false),
            ),
          );
          await tester.pumpWidget(
            makeTestable(
              const SingleChildScrollView(child: FloatingButtonSection()),
              overrides: [settingsProvider.overrideWith(() => notifier)],
            ),
          );
          await tester.pumpAndSettle();

          expect(notifier.state.value!.overlay.showFloatingButton, isFalse);

          await tester.tap(find.byType(Switch).first);
          await tester.pump();

          expect(notifier.state.value!.overlay.showFloatingButton, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'no sub-controls (dropdown/slider) rendered regardless of showFloatingButton state',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          // The size picker was removed in issue 11 (fixed 56 dp design token).
          // Only the toggle (and the FloatingButtonView in trailing) are rendered.
          for (final show in [false, true]) {
            final notifier = _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                overlay: OverlaySettings(showFloatingButton: show),
              ),
            );
            await tester.pumpWidget(
              makeTestable(
                const SingleChildScrollView(child: FloatingButtonSection()),
                overrides: [settingsProvider.overrideWith(() => notifier)],
              ),
            );
            await tester.pumpAndSettle();

            expect(
              find.byType(DropdownButton<String>),
              findsNothing,
              reason: 'showFloatingButton=$show: no dropdown expected',
            );
            expect(
              find.byType(Slider),
              findsNothing,
              reason: 'showFloatingButton=$show: no slider expected',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OverlaySection — real overlay preview
  // ══════════════════════════════════════════════════════════════════════════

  group('OverlaySection preview', () {
    testWidgets('preview absent when overlay is off', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(overlayMode: 'off'),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OverlayRealPreview), findsNothing);
      expect(find.byType(FloatingOverlayView), findsNothing);
    });

    testWidgets('preview present when overlay is floating', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(overlayMode: 'floating'),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      // FloatingOverlayView has an infinite AnimationController — pump() only.
      await tester.pump();
      await tester.pump();

      expect(find.byType(OverlayRealPreview), findsOneWidget);
      expect(find.byType(FloatingOverlayView), findsOneWidget);
    });

    testWidgets('preview key reflects normal size', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlaySize: 'normal',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      // FloatingOverlayView has an infinite AnimationController — pump() only.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-real-preview-normal')),
        findsOneWidget,
      );
    });

    testWidgets('preview key reflects compact size', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlaySize: 'compact',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      // FloatingOverlayView has an infinite AnimationController — pump() only.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-real-preview-compact')),
        findsOneWidget,
      );
    });

    testWidgets('size dropdown change updates preview key immediately', (
      tester,
    ) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlaySize: 'normal',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      // FloatingOverlayView has an infinite AnimationController — pump() only.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-real-preview-normal')),
        findsOneWidget,
      );

      notifier.updateSettings((s) => s.copyWith(overlaySize: 'compact'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-real-preview-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('overlay-real-preview-normal')),
        findsNothing,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // FloatingButtonSection — real button in trailing row
  // ══════════════════════════════════════════════════════════════════════════

  group('FloatingButtonSection button in trailing', () {
    testWidgets('FloatingButtonView always present in row on Windows', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        for (final show in [false, true]) {
          final notifier = _FakeSettingsNotifier(
            AppSettings.defaults.copyWithSections(
              overlay: OverlaySettings(showFloatingButton: show),
            ),
          );
          await tester.pumpWidget(
            makeTestable(
              const SingleChildScrollView(child: FloatingButtonSection()),
              overrides: [settingsProvider.overrideWith(() => notifier)],
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(FloatingButtonView),
            findsOneWidget,
            reason:
                'FloatingButtonView must be in trailing regardless of '
                'showFloatingButton=$show',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('FloatingButtonView always present in row on macOS', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: FloatingButtonSection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonView), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('entire section hidden on Linux (no FloatingButtonView)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            overlay: const OverlaySettings(showFloatingButton: true),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: FloatingButtonSection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonView), findsNothing);
        expect(find.byType(Switch), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
