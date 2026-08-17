import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'linux_snippet_picker_controller.dart';
import 'macos_snippet_picker_controller.dart';
import 'snippet_picker_controller_interface.dart';
import 'windows_snippet_picker_controller.dart';

export 'snippet_picker_controller_interface.dart';

/// Single source of truth for "does this platform have a native
/// Snippet-Picker panel at all?" (ticket 26).
///
/// Previously this was only implicit in [createSnippetPickerController]
/// returning `null`, discoverable at runtime as
/// [SnippetPickerShowResult.unavailable] — too late for a settings row
/// (ticket 27) to decide whether to offer the hotkey at all. Defined here,
/// once, so both the hotkey dispatch path (ticket 26) and later UI (tickets
/// 27/29/30) read the same answer instead of re-deriving it.
///
/// macOS, Windows, and Linux (visual-refresh-2026 tickets 06/29/30) — full
/// three-platform parity.
bool get snippetPickerAvailableOnPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// [snippetPickerAvailableOnPlatform] as a provider — the same answer, reached
/// the way the UI reaches everything else.
///
/// Exists because the getter reads `Platform` directly and a widget test can
/// therefore only ever see the host it runs on: the „nicht verfügbar"-Zweig of
/// the settings row and the Snippets page (ticket 27) would have no test at
/// all on a macOS machine. Deliberately delegating rather than re-deriving —
/// ticket 30 still only needs a new branch here, and an override in a test
/// is a stand-in for a different platform, not a second stored truth.
final snippetPickerAvailabilityProvider = Provider<bool>(
  (ref) => snippetPickerAvailableOnPlatform,
);

/// Creates the platform-specific [SnippetPickerController], or `null` if
/// the current platform is unsupported (see [snippetPickerAvailableOnPlatform]).
SnippetPickerController? createSnippetPickerController() {
  if (Platform.isMacOS) return MacOSSnippetPickerController();
  if (Platform.isWindows) return WindowsSnippetPickerController();
  if (Platform.isLinux) return LinuxSnippetPickerController();
  return null;
}

/// Provider wrapper around [createSnippetPickerController] — unlike the
/// button/overlay controllers (constructed directly inside their service's
/// `createController()`), this one is a real provider so tests can override
/// it with a fake and drive [SnippetPickerService] through
/// [ProviderContainer], the same way [desktopPasteControllerProvider] lets
/// `RecordingOrchestrator` tests fake the native paste bridge. Disposal is
/// owned by [FloatingPlatformServiceBase], not by this provider — it has
/// exactly one consumer.
final snippetPickerControllerProvider = Provider<SnippetPickerController?>(
  (ref) => createSnippetPickerController(),
);
