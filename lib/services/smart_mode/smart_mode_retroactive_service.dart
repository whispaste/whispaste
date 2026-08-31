/// Applies a Smart Mode preset to an existing history entry's raw content on
/// demand (Smart-Mode-v2 ticket 05).
///
/// Reuses the same local engine and prompts as the live pipeline
/// ([RecordingOrchestrator], tickets 02/03), but unlike the live path this
/// surfaces failures to the caller instead of silently falling back: there
/// is no paste-in-flight to protect here (ADR 0009's never-blocks principle
/// is a live-dictation concern), and silently leaving the edited version
/// unchanged without telling the user would just look like the action did
/// nothing. The caller decides what "surfacing" means (toast, dialog, ...).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/pipeline_step_runner.dart';
import 'smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import 'smart_mode_model_download_service.dart' show smartModeDownloadProvider;
import 'smart_mode_presets.dart';

/// Why [SmartModeRetroactiveResult] failed, for callers that want to show a
/// tailored message (e.g. "model not downloaded" vs. a generic error).
enum SmartModeRetroactiveFailureReason {
  modelMissing,
  timeout,
  engineError,
  blankResult,
}

/// Outcome of [SmartModeRetroactiveService.apply].
sealed class SmartModeRetroactiveResult {
  const SmartModeRetroactiveResult();
}

/// The preset ran successfully; [editedContent] is ready to be persisted as
/// the entry's new "current edited version".
final class SmartModeRetroactiveSuccess extends SmartModeRetroactiveResult {
  const SmartModeRetroactiveSuccess(this.editedContent);

  final String editedContent;
}

/// The preset failed for [reason]. The caller must leave the entry's
/// existing edited version (if any) untouched — no silent data loss.
final class SmartModeRetroactiveFailure extends SmartModeRetroactiveResult {
  const SmartModeRetroactiveFailure(this.reason);

  final SmartModeRetroactiveFailureReason reason;
}

class SmartModeRetroactiveService {
  SmartModeRetroactiveService(this._ref);

  final Ref _ref;

  static const _timeout = Duration(seconds: 15);

  /// Test-only override for [_timeout] — mirrors
  /// `RecordingOrchestrator.smartModeCleanupTimeoutOverride`.
  @visibleForTesting
  static Duration? timeoutOverride;

  /// Runs [preset] over [rawText] and returns either the new edited content
  /// or a typed failure reason. [preset] must not be [SmartModePreset.off]
  /// — callers only offer this action for the three real presets.
  /// [targetLanguage] is required for [SmartModePreset.translate] (the
  /// per-entry choice from ticket 05, distinct from the live pipeline's
  /// global default) and ignored otherwise.
  Future<SmartModeRetroactiveResult> apply({
    required String rawText,
    required SmartModePreset preset,
    SmartModeTargetLanguage? targetLanguage,
  }) async {
    if (!_ref.read(smartModeDownloadProvider).modelDownloaded) {
      return const SmartModeRetroactiveFailure(
        SmartModeRetroactiveFailureReason.modelMissing,
      );
    }

    final systemPrompt = smartModeSystemPromptFor(
      preset,
      targetLanguage: targetLanguage,
    );

    final runner = PipelineStepRunner(timeout: timeoutOverride ?? _timeout);
    final result = await runner.run<String>(
      'smart_mode_retroactive',
      () => _ref
          .read(smartModeEngineProvider)
          .run(systemPrompt: systemPrompt, userText: rawText),
    );

    switch (result) {
      case Ok(:final value):
        if (value.trim().isEmpty) {
          return const SmartModeRetroactiveFailure(
            SmartModeRetroactiveFailureReason.blankResult,
          );
        }
        return SmartModeRetroactiveSuccess(value);
      case StepTimeout():
        return const SmartModeRetroactiveFailure(
          SmartModeRetroactiveFailureReason.timeout,
        );
      case FailedWith():
        return const SmartModeRetroactiveFailure(
          SmartModeRetroactiveFailureReason.engineError,
        );
    }
  }
}

final smartModeRetroactiveServiceProvider =
    Provider<SmartModeRetroactiveService>(SmartModeRetroactiveService.new);
