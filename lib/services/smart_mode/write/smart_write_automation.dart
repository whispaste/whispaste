/// The write path behind `POST /v1/write` (#255, ADR 0015 D22).
///
/// Same engine call as the Smart Mode hotkey's write route: the written
/// instruction takes the place of the transcript. There is no preview and
/// no Enter step, so the target check runs right before the paste instead:
/// the app that was in front when the request came in must still be in
/// front and must be the app the paste path captured. On Wayland that check
/// is impossible and the text is pasted with the D18 hint. A failed check
/// pastes nothing and copies nothing: the caller may be a script with no
/// one at the screen, and the clipboard is the user's. Logs carry lengths
/// and codes only, never text.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/recording/recording_state.dart'
    show isDictationBusy, recordingPhaseProvider;
import '../../automation_api/automation_write_jobs.dart';
import '../../paste/paster.dart';
import '../../selection_edit/selection_edit_preview.dart'
    show selectionEditPasteOptions;
import 'smart_write_environment.dart';
import 'smart_write_preview.dart';
import 'smart_write_service.dart';

final _log = AppLogger('SmartWriteAutomation');

const _nativeTimeout = Duration(seconds: 5);

class SmartWriteAutomationRunner implements AutomationWriteRunner {
  SmartWriteAutomationRunner(
    this._ref, {
    required this._preflight,
    this.dictationWait = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 200),
  });

  final Ref _ref;
  final Future<String?> Function() _preflight;

  /// How long a paste waits for a running dictation to finish. The job
  /// never blocks the dictation (R19); it is the job that waits, so it does
  /// not take over the dictation's captured paste target.
  final Duration dictationWait;
  final Duration pollInterval;

  SmartWriteEnvironment get _environment =>
      _ref.read(smartWriteEnvironmentProvider);

  @override
  Future<AutomationWriteTarget> captureTarget() async {
    final environment = _environment;
    if (environment.wayland) return const AutomationWriteTarget(wayland: true);
    final front = await environment.foreground().timeout(_nativeTimeout);
    if (front == null || front.isOwn) return const AutomationWriteTarget();
    return AutomationWriteTarget(id: front.id);
  }

  @override
  Future<String?> preflight() => _preflight();

  @override
  Future<AutomationWriteDraft> write(
    String instruction,
    AutomationWriteContextLimits limits,
  ) async {
    // The hotkey's write route sends the instruction only, so there is no
    // context source yet for [limits] to switch off. Once context arrives
    // (ADR 0015 D14/D20) it has to honour these limits here.
    final outcome = await _ref
        .read(smartWriteServiceProvider)
        .write(instruction: instruction);
    final text = outcome.text;
    if (text != null) return AutomationWriteDraft.text(text);
    return AutomationWriteDraft.failed(
      outcome.failure?.errorCode ?? 'smart_write_failed',
    );
  }

  @override
  Future<String?> insert(
    String text,
    AutomationWriteTarget target, {
    required bool Function() stillAllowed,
  }) async {
    if (!await _dictationIdle()) return 'automation_write_dictation_busy';
    if (!stillAllowed()) return 'revoked';
    final paster = _ref.read(pasterProvider);
    if (paster == null) return 'automation_write_paste_failed';
    final environment = _environment;
    if (!target.wayland) {
      final front = await environment.foreground().timeout(_nativeTimeout);
      if (front == null || front.isOwn || front.id != target.id) {
        return 'automation_write_target_changed';
      }
      // Capture the paste target, then check that the capture is the app
      // just checked (same double check as the preview's Enter path).
      await paster.prime().timeout(_nativeTimeout);
      final captured = await environment.target().timeout(_nativeTimeout);
      final checked = await environment.foreground().timeout(_nativeTimeout);
      if (captured != target.id ||
          checked?.id != target.id ||
          checked?.isOwn != false) {
        return 'automation_write_target_changed';
      }
    } else {
      _log.info('API write paste: target unverifiable on Wayland (D18)');
    }
    if (!stillAllowed()) return 'revoked';
    final settings = _ref.read(settingsProvider).value ?? AppSettings.defaults;
    final outcome = await paster.paste(
      text,
      selectionEditPasteOptions(settings),
    );
    if (outcome != PasteOutcome.success) {
      _log.info('API write paste not confirmed (outcome=${outcome.name})');
      return 'automation_write_paste_failed';
    }
    _ref
        .read(smartWriteNoticeProvider.notifier)
        .announce(
          target.wayland
              ? SmartWriteHint.automationInsertedWayland
              : SmartWriteHint.automationInserted,
        );
    return null;
  }

  Future<bool> _dictationIdle() async {
    final deadline = DateTime.now().add(dictationWait);
    while (isDictationBusy(_ref.read(recordingPhaseProvider))) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(pollInterval);
    }
    return true;
  }
}
