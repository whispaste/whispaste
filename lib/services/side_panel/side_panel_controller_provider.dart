import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'method_channel_side_panel_controller.dart';
import 'side_panel_controller_interface.dart';

/// Real provider (rather than constructing directly inside
/// [SidePanelService.createController]) so tests can override it with a
/// fake, mirroring `snippetPickerControllerProvider`. Disposal is owned by
/// [FloatingPlatformServiceBase], not by this provider -- it has exactly
/// one consumer.
final sidePanelControllerProvider = Provider<SidePanelController?>(
  (ref) => MethodChannelSidePanelController(),
);
