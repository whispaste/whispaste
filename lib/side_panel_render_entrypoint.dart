/// Dedicated Flutter entrypoint for the clipboard quick-paste side-panel
/// render engine.
///
/// Mirrors the floating-overlay render engine (`floating_overlay_render_
/// entrypoint.dart`): the native per-monitor panel window is a lifecycle-only
/// shell that hosts a **second, headless-ish Flutter engine** whose only job
/// is to paint [WpSidePanelView]. That engine is booted by the native panel
/// host with the `sidePanelMain` entrypoint (macOS/Windows) or the
/// `--side-panel` Dart entrypoint argument (Linux).
///
/// ## The seam
///
/// The app's MAIN engine is untouched: [SidePanelService] still pushes
/// `updateSnapshot` over the `com.whispaste.side_panel` channel to the
/// native host. The host then **relays** that payload to THIS engine over a
/// private render channel ([_renderChannelName]). Interaction goes the other
/// way: this engine reports a row click or the pointer leaving the panel --
/// the host translates that into the existing `com.whispaste.side_panel`
/// event contract, unchanged. So the whole service/controller/event contract
/// stays exactly as it was; only the pixels move to this engine.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'services/side_panel/side_panel_render_channel.dart';
import 'services/side_panel/side_panel_snapshot.dart';
import 'shared_render_engine_helpers.dart';
import 'widgets/side_panel/side_panel_view.dart';

/// How long the pointer may be off the panel before it actually closes.
///
/// Without this grace period, a pointer that clips the panel's edge for a
/// frame (e.g. crossing from the sensor strip into the panel, or a brief
/// wobble while aiming at a row) fires `MouseRegion.onExit` and closes the
/// panel out from under the user. [_SidePanelRenderAppState] cancels the
/// pending close if the pointer re-enters before this elapses.
const Duration _closeGracePeriod = Duration(milliseconds: 350);

/// Private channel between the native panel shell and this render engine.
///
/// Distinct from the public `com.whispaste.side_panel` channel the main
/// engine uses -- the two engines never share a binary messenger, so the
/// names must not collide.
const String _renderChannelName = 'com.whispaste.side_panel_render';

/// Boots the side-panel render engine.
///
/// The actual `@pragma('vm:entry-point') sidePanelMain` lives in `main.dart`
/// (the root library) because macOS `runWithEntrypoint:` resolves the
/// entrypoint name only against the root library -- it has no `libraryURI`
/// variant. That thin entrypoint delegates here so the real wiring stays in
/// this cohesive, unit-tested file.
void runSidePanelEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[side-panel-engine] runSidePanelEngine booted');
  runApp(const _SidePanelRenderApp());
}

class _SidePanelRenderApp extends StatefulWidget {
  const _SidePanelRenderApp();

  @override
  State<_SidePanelRenderApp> createState() => _SidePanelRenderAppState();
}

class _SidePanelRenderAppState
    extends RenderEngineState<_SidePanelRenderApp, SidePanelRenderChannel> {
  _SidePanelRenderAppState()
    : super(lookupL10n(const Locale('en')).a11ySidePanel);

  SidePanelSnapshot _snapshot = const SidePanelSnapshot();
  Timer? _closeTimer;

  @override
  SidePanelRenderChannel createChannel() => SidePanelRenderChannel(
    name: _renderChannelName,
    onSnapshot: (s) => setState(() => _snapshot = s),
  );

  @override
  String labelOf(L10n l10n) => l10n.a11ySidePanel;

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeGracePeriod, channel.hoverLeft);
  }

  void _cancelScheduledClose() => _closeTimer?.cancel();

  /// Close button pressed -- same path as hover-exit, just without the
  /// grace period (an explicit click is not a pointer wobble).
  void _closeNow() {
    _closeTimer?.cancel();
    channel.hoverLeft();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedL10n = l10n ?? lookupL10n(const Locale('en'));
    return Localizations(
      locale: Locale(resolvedL10n.localeName),
      delegates: L10n.localizationsDelegates,
      child: Directionality(
        textDirection: TextDirection.ltr,
        // No Scaffold and no background fill: the engine surface is cleared
        // by the native shell, so anything we don't paint stays transparent.
        // WpSidePanelView's own rows carry per-row Semantics/tap handling
        // already, so -- unlike the overlay/button engines -- this root
        // deliberately does not wrap the tree in a single opaque
        // RenderEngineGestureLayer, which would compete with those row-level
        // GestureDetectors for the same tap. MouseRegion only tracks hover
        // and never intercepts hit-testing, so it composes cleanly instead.
        //
        // `Material(type: transparency)` IS still required, though (issue
        // 09's search field): it paints nothing and never intercepts hit
        // testing, but `TextField` asserts a `Material` ancestor to host its
        // ink/decoration internals -- without it the field throws "No
        // Material widget found" on every build, which cascades into a
        // garbage intrinsic size and a `RenderFlex overflowed` error on the
        // panel's outer Column.
        //
        // `Overlay` wraps that `Material` for the same reason, one layer up:
        // the search field's clear button is an `IconButton(tooltip: ...)`,
        // and `Tooltip` shows itself by inserting an `OverlayEntry` -- with
        // no `Navigator`/`MaterialApp` in this engine there is no ambient
        // `Overlay` to insert into, so the clear button throws "No Overlay
        // widget found" the moment typed text makes it appear, which again
        // cascades into a `RenderFlex overflowed` on the panel's Column.
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Material(
                type: MaterialType.transparency,
                child: Semantics(
                  container: true,
                  label: semanticsLabel,
                  child: MouseRegion(
                    onEnter: (_) => _cancelScheduledClose(),
                    onExit: (_) => _scheduleClose(),
                    child: WpSidePanelView(
                      snapshot: _snapshot,
                      onRowTap: (section, id) {
                        debugPrint(
                          '[side-panel-engine] row tapped: ${section.name}/$id '
                          'at ${DateTime.now()}',
                        );
                        channel.rowClicked(section, id);
                      },
                      onRowDragStart: (section, row) {
                        debugPrint(
                          '[side-panel-engine] row drag started: '
                          '${section.name}/${row.id} at ${DateTime.now()}',
                        );
                        channel.beginDrag(section, row);
                      },
                      onClose: _closeNow,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
