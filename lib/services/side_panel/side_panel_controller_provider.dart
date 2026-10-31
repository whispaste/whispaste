import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'method_channel_side_panel_controller.dart';
import 'side_panel_controller_interface.dart';

/// Real provider (rather than constructing directly inside
/// [SidePanelService.createController]) so tests can override it with a
/// fake, mirroring `snippetPickerControllerProvider`.
///
/// `.autoDispose`, unlike `snippetPickerControllerProvider`: that one is
/// safe as a plain (permanently cached) `Provider` only because
/// `snippetPickerServiceProvider` is itself a plain (non-autoDispose)
/// `NotifierProvider` whose `build()` runs exactly once per process, so its
/// `ref.read` here never repeats. `sidePanelServiceProvider` **is**
/// `.autoDispose` and gets rebuilt every time the user toggles the panel
/// setting off and back on -- [SidePanelService.createController] must
/// `ref.watch` (not `ref.read`) this provider so that disposal is
/// symmetric: [FloatingPlatformServiceBase]'s `ref.onDispose` calls
/// `disposeController`, which permanently latches the returned
/// `MethodChannelSidePanelController`'s internal `isDisposed` flag (see
/// `MethodChannelPlatformHost.dispose()`) -- a toggle-off followed by a
/// toggle-on that read the SAME cached instance would silently no-op every
/// `invokeMethod` call forever after. Watching this provider ties its own
/// lifetime to `SidePanelService`'s: when the setting turns the panel back
/// on and `SidePanelService` rebuilds, this provider has lost its only
/// watcher in between and reruns its create function, handing back a fresh,
/// un-disposed controller.
final sidePanelControllerProvider = Provider.autoDispose<SidePanelController?>(
  (ref) => MethodChannelSidePanelController(),
);
