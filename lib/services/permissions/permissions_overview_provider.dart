/// One list of the permissions WhisPaste needs, for any surface that shows
/// them together (the onboarding permission step now, a Settings section
/// later).
///
/// This is a read-only facade over the two existing notifiers — it never
/// probes, prompts or polls itself, so watching it is free. Each surface keeps
/// its own actions; this only answers "which permission stands where".
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../paste/paste_capability_notifier.dart';
import '../paste/paster.dart';
import 'mic_permission_notifier.dart';

enum PermissionOverviewId { microphone, autoPaste }

enum PermissionOverviewStatus { granted, missing, pending }

@immutable
class PermissionOverviewEntry {
  const PermissionOverviewEntry({
    required this.id,
    required this.status,
    required this.optional,
  });

  final PermissionOverviewId id;
  final PermissionOverviewStatus status;

  /// `true` when the flow lets the user continue without it. Auto-Paste is
  /// optional (the clipboard path still works); the microphone is not.
  final bool optional;

  @override
  bool operator ==(Object other) =>
      other is PermissionOverviewEntry &&
      other.id == id &&
      other.status == status &&
      other.optional == optional;

  @override
  int get hashCode => Object.hash(id, status, optional);
}

/// The permissions that apply on the current platform, in display order.
///
/// Linux has no microphone or paste permission surface in WhisPaste, and the
/// Auto-Paste permission does not exist on Windows (it needs none), so each
/// entry is omitted where it does not apply rather than shown as "granted".
/// Auto-Paste is kept on every other platform: the onboarding step renders its
/// macOS body everywhere but Windows, and tests run under the Android default.
final permissionsOverviewProvider = Provider<List<PermissionOverviewEntry>>((
  ref,
) {
  final platform = defaultTargetPlatform;
  final entries = <PermissionOverviewEntry>[];

  if (platform != TargetPlatform.linux) {
    final mic = ref.watch(micPermissionNotifierProvider).status;
    entries.add(
      PermissionOverviewEntry(
        id: PermissionOverviewId.microphone,
        status: switch (mic) {
          MicPermissionStatus.granted => PermissionOverviewStatus.granted,
          MicPermissionStatus.denied => PermissionOverviewStatus.missing,
          MicPermissionStatus.unknown ||
          MicPermissionStatus.requesting => PermissionOverviewStatus.pending,
        },
        optional: false,
      ),
    );
  }

  if (platform != TargetPlatform.windows && platform != TargetPlatform.linux) {
    final paste = ref.watch(pasteCapabilityNotifierProvider).capability?.status;
    final status = switch (paste) {
      PasteCapabilityStatus.ready => PermissionOverviewStatus.granted,
      PasteCapabilityStatus.permissionMissing =>
        PermissionOverviewStatus.missing,
      PasteCapabilityStatus.unsupported => null,
      null => PermissionOverviewStatus.pending,
    };
    if (status != null) {
      entries.add(
        PermissionOverviewEntry(
          id: PermissionOverviewId.autoPaste,
          status: status,
          optional: true,
        ),
      );
    }
  }

  return entries;
});
