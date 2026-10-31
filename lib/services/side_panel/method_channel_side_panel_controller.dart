import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'side_panel_controller_interface.dart';
import 'side_panel_events.dart';
import 'side_panel_snapshot.dart';

/// Single cross-platform implementation of [SidePanelController].
///
/// Unlike the button/overlay/snippet-picker controllers, nothing here
/// differs by platform (yet): one channel, one wire format, no native
/// counterpart at all before issue 04. Split into per-platform subclasses
/// only if issues 04-06 turn up an actual difference worth one.
class MethodChannelSidePanelController
    extends MethodChannelPlatformHost<SidePanelEvent>
    implements SidePanelController {
  static const _channelName = 'com.whispaste.side_panel';

  MethodChannelSidePanelController() : super(_channelName);

  @override
  Future<void> updateSnapshot(SidePanelSnapshot snapshot) =>
      invokeMethod('updateSnapshot', snapshot.toMap());

  @override
  SidePanelEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'rowClicked':
        final args = call.arguments;
        if (args is! Map) return null;
        final sectionName = args['section'] as String?;
        final id = args['id'] as String?;
        if (sectionName == null || id == null) return null;
        for (final section in SidePanelSection.values) {
          if (section.name == sectionName) {
            return SidePanelRowClicked(section, id);
          }
        }
        return null;
      case 'hoverLeft':
        return const SidePanelHoverLeft();
      case 'hoverEntered':
        return const SidePanelHoverEntered();
      default:
        return null;
    }
  }
}
