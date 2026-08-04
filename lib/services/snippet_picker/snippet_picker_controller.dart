import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'macos_snippet_picker_controller.dart';
import 'snippet_picker_controller_interface.dart';

export 'snippet_picker_controller_interface.dart';

/// Creates the platform-specific [SnippetPickerController], or `null` if
/// the current platform is unsupported.
///
/// macOS only for now (dictation-automations ticket 06) — Windows/Linux
/// implementations land in tickets 07/08 behind the same interface.
SnippetPickerController? createSnippetPickerController() {
  if (Platform.isMacOS) return MacOSSnippetPickerController();
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
