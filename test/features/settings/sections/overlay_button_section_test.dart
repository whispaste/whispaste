/// Round-trip widget tests for [OverlaySection] and [FloatingButtonSection].
///
/// Covers:
/// - OverlaySection: toggle round-trip (overlayMode off → floating), nested
///   overlay dropdowns hidden when off and visible when floating.
/// - OverlaySection: preview widget visibility, position and size reflection.
/// - FloatingButtonSection: toggle round-trip (showFloatingButton false → true).
///   No sub-controls (size picker was removed in issue 11 — fixed 56 dp).
///
/// Platform notes:
/// - OverlaySection renders the toggle on all desktop platforms
///   (Windows / macOS / Linux).
/// - FloatingButtonSection renders only on Windows and macOS; tests for it
///   use a runtime platform guard instead of `skip` so they pass vacuously on
///   Linux CI rather than being counted as skipped.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
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

bool get _isFloatingButtonPlatform => Platform.isWindows || Platform.isMacOS;

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
        await tester.pumpAndSettle();

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
      'renders on macOS / Windows, empty SizedBox on other platforms',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: FloatingButtonSection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        if (_isFloatingButtonPlatform) {
          // Section should render with at least the toggle Switch.
          expect(find.byType(Switch), findsOneWidget);
        } else {
          // Unsupported platform: widget tree is empty (SizedBox.shrink).
          expect(find.byType(Switch), findsNothing);
        }
      },
    );

    testWidgets(
      'floating button toggle round-trip updates overlay.showFloatingButton',
      (tester) async {
        if (!_isFloatingButtonPlatform) return; // Platform guard.

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
      },
    );

    testWidgets(
      'no sub-controls rendered regardless of showFloatingButton state',
      (tester) async {
        if (!_isFloatingButtonPlatform) return; // Platform guard.

        // The size picker was removed in issue 11 (fixed 56 dp design token).
        // The toggle is the only interactive control in this section.
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
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OverlaySection — preview widget
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

      expect(find.byType(OverlayPositionPreview), findsNothing);
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
      await tester.pumpAndSettle();

      expect(find.byType(OverlayPositionPreview), findsOneWidget);
    });

    testWidgets('preview key reflects top-center position', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlayStartPosition: 'top-center',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-top-center')),
        findsOneWidget,
      );
    });

    testWidgets('preview key reflects bottom-center position', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlayStartPosition: 'bottom-center',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-bottom-center')),
        findsOneWidget,
      );
    });

    testWidgets('preview key reflects last-position anchor', (tester) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlayStartPosition: 'last-position',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-last-position')),
        findsOneWidget,
      );
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
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-size-normal')),
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
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-size-compact')),
        findsOneWidget,
      );
    });

    testWidgets('position dropdown change updates preview key immediately', (
      tester,
    ) async {
      if (!_isDesktop) return; // Platform guard.

      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          overlay: const OverlaySettings(
            overlayMode: 'floating',
            overlayStartPosition: 'top-center',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: OverlaySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      // Initially top-center.
      expect(
        find.byKey(const ValueKey('overlay-pill-top-center')),
        findsOneWidget,
      );

      // Simulate settings change via notifier (mirrors dropdown round-trip).
      notifier.updateSettings(
        (s) => s.copyWith(overlayStartPosition: 'bottom-center'),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-pill-bottom-center')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('overlay-pill-top-center')),
        findsNothing,
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
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('overlay-pill-size-normal')),
        findsOneWidget,
      );

      notifier.updateSettings((s) => s.copyWith(overlaySize: 'compact'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('overlay-pill-size-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('overlay-pill-size-normal')),
        findsNothing,
      );
    });
  });
}
