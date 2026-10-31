/// Lock screen shown in place of the notes while a History PIN is set and
/// not unlocked (GS-149). The notes share the history lock, so the same PIN
/// and the same unlock dialog apply.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_shell.dart';
import '../../history/widgets/history_pin_dialogs.dart';

const kNotesPinGateKey = ValueKey('notes-pin-gate');

class NotesPinGate extends StatelessWidget {
  const NotesPinGate({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Semantics(
        identifier: 'notes-pin-gate',
        child: WpEmptyState(
          key: kNotesPinGateKey,
          icon: LucideIcons.lock,
          title: l10n.notesPinGateTitle,
          hint: l10n.notesPinGateHint,
          actionLabel: l10n.historyPinUnlock,
          onAction: () =>
              showHistoryPinUnlockDialog(context, offerForgot: true),
        ),
      ),
    );
  }
}
