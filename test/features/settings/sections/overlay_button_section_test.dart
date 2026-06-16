/// Round-trip widget tests for [OverlaySection] and [FloatingButtonSection].
///
/// Covers:
/// - OverlaySection: toggle round-trip (overlayMode off → floating), nested
///   overlay dropdowns hidden when off and visible when floating.
/// - OverlaySection: real overlay preview (OverlayRealPreview / FloatingOverlayView)
///   visibility and size reflection.
/// - FloatingButtonSection: toggle round-trip (showFloatingButton false → true).
///   FloatingButtonView is always visible in the trailing of the toggle row.
///
/// Platform notes:
/// - OverlaySection renders the toggle on all desktop platforms
///   (Windows / macOS / Linux).
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
    testWidgets('renders toggle on desktop platforms', (tester) async {
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

      if (_isDesktop) {
        expect(find.byType(Switch), findsOneWidget);
      } else {
        // Non-desktop: no overlay toggle rendered.
        expect(find.byType(Switch), findsNothing);
      }
    });

    testWidgets('nested overlay dropdowns hidden when overlayMode is off', (
      tester,
    ) async {
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

      // Only the toggle switch — no dropdowns visible.
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets(
      'overlay toggle round-trip sets overlay.overlayMode to floating',
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

        // Toggle is off initially.
        expect(notifier.state.value!.overlay.overlayMode, 'off');

        await tester.tap(find.byType(Switch).first);
        await tester.pump();

        expect(
          notifier.state.value!.overlay.overlayMode,
          OverlayMode.floating.value,
        );
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
