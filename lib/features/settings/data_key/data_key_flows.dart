/// Entry points of the data-key flows behind Settings → Privacy (#1165).
///
/// Backing up uses the flow of #1166 directly (`data_key_backup_flow.dart`).
/// Restoring a lost key, or knowingly creating a new one, is the flow of
/// #1167 (`data_key_restore_flow.dart`), also offered on the start screen of
/// a locked history; tests replace both via the providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_key_restore_flow.dart';

/// Starts a data-key flow from [context].
typedef DataKeyFlow = Future<void> Function(BuildContext context);

/// Starts a restore from [context]; true when the key is back.
typedef DataKeyRestoreFlow = Future<bool> Function(BuildContext context);

/// "Restore": the restore flow (#1167).
final dataKeyRestoreFlowProvider = Provider<DataKeyFlow>(
  (ref) => startDataKeyRestore,
);

/// "Restore" on the start screen of a locked history: the same dialog,
/// without "Create new key" and without a notice.
final dataKeyLockedRestoreFlowProvider = Provider<DataKeyRestoreFlow>(
  (ref) =>
      (context) => startDataKeyRestore(context, fromStartup: true),
);
