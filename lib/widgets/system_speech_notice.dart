import 'package:flutter/material.dart';

import 'dictation_message.dart';
import 'onboarding_hold.dart';

/// Calm, informational toast for a recording that Apple speech handed to
/// Whisper. It names the fact and asks nothing, so it needs no action.
void showWpSystemSpeechFallbackToast({
  required BuildContext context,
  required String message,
}) {
  showWpDictationMessage(
    context,
    message: message,
    type: WpMessageType.info,
    duration: const Duration(seconds: 6),
    testId: 'system-speech-fallback-toast',
  );
}
