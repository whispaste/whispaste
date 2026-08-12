import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'macos_snippet_picker_controller.dart';
import 'snippet_picker_controller_interface.dart';

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
/// macOS only for now (dictation-automations ticket 06) — Windows/Linux
/// implementations land in tickets 07/08 behind the same interface, at
/// which point this is the one place to update.
bool get snippetPickerAvailableOnPlatform => Platform.isMacOS;

/// Creates the platform-specific [SnippetPickerController], or `null` if
/// the current platform is unsupported (see [snippetPickerAvailableOnPlatform]).
SnippetPickerController? createSnippetPickerController() {
  if (snippetPickerAvailableOnPlatform) return MacOSSnippetPickerController();
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
