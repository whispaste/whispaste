/// Call-site adapter of the dictation pipeline's messages (#453).
///
/// Takes the message and options of a toast-style call and puts it on the overlay
/// card (or, with the overlay off, in the main window) through
/// [showDictationNotice]. Errors, notices with a button and notices about a loss stay until closed;
/// pure status hints close themselves.
/// Not a component of its own.
library;

import 'package:flutter/widgets.dart';

import '../core/logging/app_logger.dart';
import '../services/floating_overlay/dictation_notice.dart';
import '../services/floating_overlay/overlay_notice.dart';
import 'onboarding_hold.dart' show WpMessageAction, WpMessageType;
import 'wp_error_notice.dart';

final _log = AppLogger('DictationMessage');

/// Shows [message] where the user looks while dictating. [body] with a
/// [WpErrorNotice] splits it into cause and next step. [actionId] names what
/// the button does (a [WpMessageAction.testId] wins), [detail] is an extra line
/// below the message. A second button ([secondActionLabel], [onSecondAction],
/// [secondActionId]) is the alternative to the first one and shows only
/// together with it.
void showWpDictationMessage(
  BuildContext context, {
  required String message,
  WpMessageType type = WpMessageType.info,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
  WpMessageAction? action,
  Widget? body,
  String? testId,
  String? actionId,
  String detail = '',
  bool keepOpen = false,
  String? actionConfirmation,
  String? secondActionLabel,
  VoidCallback? onSecondAction,
  String? secondActionId,
  bool offersNewDictation = true,
}) {
  final label = action?.label ?? actionLabel;
  final callback = action?.onPressed ?? onAction;
  final isError = type == WpMessageType.error;
  var cause = message;
  var nextStep = '';
  if (body is WpErrorNotice) {
    cause = body.cause;
    nextStep = body.nextStep ?? '';
  }
  // A pure status or success notice stays for a time that fits its length.
  // Anything that offers a button (WCAG 2.2.1: time to act), an error, and a
  // message that reports a loss or a dead hotkey ([keepOpen]) stays until it
  // is closed (#781).
  final hasAction = label != null && callback != null;
  // The second button is the alternative to the first: it never stands alone.
  final hasSecond =
      hasAction && secondActionLabel != null && onSecondAction != null;
  final textTime = dictationNoticeTime('$cause $nextStep');
  final shown = duration == null || duration < textTime ? textTime : duration;
  _log.debug('Dictation message (${type.name}): ${testId ?? cause}');
  showDictationNotice(
    context,
    DictationNotice(
      id: testId ?? type.name,
      offersNewDictation: offersNewDictation,
      cause: cause,
      nextStep: nextStep,
      detail: detail,
      tone: isError ? OverlayNoticeTone.error : OverlayNoticeTone.hint,
      autoDismiss: isError || keepOpen || hasAction ? null : shown,
      actions: [
        if (hasAction)
          DictationNoticeAction(
            id: action?.testId ?? actionId ?? 'action',
            label: label,
            onPressed: callback,
            confirmation: actionConfirmation,
          ),
        if (hasSecond)
          DictationNoticeAction(
            id: secondActionId ?? 'second-action',
            label: secondActionLabel,
            onPressed: onSecondAction,
          ),
      ],
    ),
  );
}
