/// Dialogs for the History PIN lock: entering the current PIN (unlock, and
/// confirming before the PIN is changed or removed) and choosing a new one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_text_field.dart';
import '../data/history_lock.dart';
import '../data/history_pin.dart';

@visibleForTesting
const kHistoryPinFieldKey = Key('historyPinField');
@visibleForTesting
const kHistoryPinRepeatFieldKey = Key('historyPinRepeatField');
@visibleForTesting
const kHistoryPinSubmitKey = Key('historyPinSubmit');
@visibleForTesting
const kHistoryPinForgotKey = Key('historyPinForgot');

/// Asks for the current PIN and checks it (throttled). Returns `true` once
/// the right PIN was entered — which also unlocks the history — or, when
/// [offerForgot] is set, after the user chose "Forgot PIN?" and the history
/// was wiped.
Future<bool> showHistoryPinUnlockDialog(
  BuildContext context, {
  bool offerForgot = false,
}) async {
  final result = await showWpFormDialog<bool>(
    context: context,
    builder: (ctx, animation) =>
        _UnlockDialog(animation: animation, offerForgot: offerForgot),
  );
  return result ?? false;
}

/// Asks for a new PIN twice. Returns the validated PIN, or `null` when
/// cancelled.
Future<String?> showHistoryPinSetDialog(BuildContext context) {
  return showWpFormDialog<String>(
    context: context,
    builder: (ctx, animation) => _SetPinDialog(animation: animation),
  );
}

class _UnlockDialog extends ConsumerStatefulWidget {
  const _UnlockDialog({required this.animation, required this.offerForgot});

  final Animation<double> animation;
  final bool offerForgot;

  @override
  ConsumerState<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends ConsumerState<_UnlockDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(historyRevealedProvider.notifier)
        .unlockWithPin(_pin.text.trim());
    if (!mounted) return;
    if (result.outcome == HistoryPinOutcome.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _pin.clear();
    setState(() {
      _busy = false;
      _error = result.outcome == HistoryPinOutcome.wrong
          ? l10n.historyPinWrong
          : l10n.historyPinLockedOut(result.retryAfter.inSeconds + 1);
    });
  }

  Future<void> _forgot() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.historyPinForgotConfirmTitle,
      message: l10n.historyPinForgotConfirmMessage,
      confirmLabel: l10n.historyPinForgotConfirmAction,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(historyRevealedProvider.notifier).resetForgottenPin();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.historyPinDialogTitle,
      subtitle: l10n.historyPinDialogSubtitle,
      fields: [
        WpTextField(
          key: kHistoryPinFieldKey,
          controller: _pin,
          variant: WpTextFieldVariant.form,
          hintText: l10n.historyPinFieldHint,
          semanticsLabel: l10n.historyPinFieldHint,
          obscureText: true,
          autocorrect: false,
          autofocus: true,
          maxLength: 8,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) _ErrorText(_error!),
        if (widget.offerForgot) ...[
          const SizedBox(height: WpSpacing.sm),
          WpButton(
            key: kHistoryPinForgotKey,
            label: l10n.historyPinForgot,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.danger,
            onPressed: _busy ? null : _forgot,
          ),
        ],
      ],
      actions: [
        WpButton(
          label: l10n.actionCancel,
          variant: WpButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: WpSpacing.sm),
        WpButton(
          key: kHistoryPinSubmitKey,
          label: l10n.historyPinUnlock,
          variant: WpButtonVariant.primary,
          isLoading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog({required this.animation});

  final Animation<double> animation;

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = L10n.of(context);
    final pin = _pin.text.trim();
    final String? error;
    if (!isValidHistoryPin(pin)) {
      error = l10n.historyPinInvalid;
    } else if (pin != _repeat.text.trim()) {
      error = l10n.historyPinMismatch;
    } else {
      error = null;
    }
    if (error == null) {
      Navigator.of(context).pop(pin);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.historyPinSetTitle,
      subtitle: l10n.historyPinSetSubtitle,
      fields: [
        WpTextField(
          key: kHistoryPinFieldKey,
          controller: _pin,
          variant: WpTextFieldVariant.form,
          hintText: l10n.historyPinFieldHint,
          semanticsLabel: l10n.historyPinFieldHint,
          obscureText: true,
          autocorrect: false,
          autofocus: true,
          maxLength: 8,
        ),
        const SizedBox(height: WpSpacing.sm),
        WpTextField(
          key: kHistoryPinRepeatFieldKey,
          controller: _repeat,
          variant: WpTextFieldVariant.form,
          hintText: l10n.historyPinRepeatHint,
          semanticsLabel: l10n.historyPinRepeatHint,
          obscureText: true,
          autocorrect: false,
          maxLength: 8,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) _ErrorText(_error!),
      ],
      actions: [
        WpButton(
          label: l10n.actionCancel,
          variant: WpButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: WpSpacing.sm),
        WpButton(
          key: kHistoryPinSubmitKey,
          label: l10n.historyPinSetTitle,
          variant: WpButtonVariant.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: WpColors.error),
      ),
    );
  }
}
