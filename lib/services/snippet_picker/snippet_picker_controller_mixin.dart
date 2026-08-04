import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'snippet_picker_events.dart';

/// Shared [parseNativeEvent] implementation for all platform-specific
/// [SnippetPickerController] classes (tickets 06/07/08 all use the same
/// channel protocol) — mirrors [FloatingButtonControllerMixin].
mixin SnippetPickerControllerMixin
    on MethodChannelPlatformHost<SnippetPickerEvent> {
  @override
  SnippetPickerEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onItemSelected':
        final args = call.arguments as Map?;
        final id = args?['id'] as String?;
        if (id != null) return SnippetPickerItemSelected(id);
        return null;
      case 'onCancelled':
        return const SnippetPickerCancelled();
      case 'onRenderEngineDiagnostic':
        final args = call.arguments as Map?;
        final message = (args?['message'] as String?) ?? 'unknown';
        final isError = (args?['isError'] as bool?) ?? false;
        return SnippetPickerRenderEngineDiagnostic(message, isError: isError);
      default:
        return null;
    }
  }
}
