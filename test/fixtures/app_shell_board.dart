/// The WP-20 app shell as one board: title band, sidebar, page header with its
/// list, and the recording dock. The shell goldens and the layout geometry
/// tests both build it from here, so a geometry assertion and a golden always
/// measure the same composition.
library;

import 'package:flutter/material.dart';
import 'package:whispaste/app.dart'
    show
        wpHelpNavItem,
        wpNavDividerAfterIds,
        wpNavItems,
        wpSettingsNavItem,
        wpSmartModePresetLabel;
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/app_shell.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';
import 'package:whispaste/widgets/wp_page_header.dart';
import 'dock_choice_fixtures.dart';

/// Speech-group value the board shows, as the dock reads it from settings.
const String kBoardSttLabel = 'Whisper · small';

Widget _row(WpThemeColors set, String label) {
  return WpListTileSurface(
    variant: WpListTileVariant.panel,
    child: Text(
      label,
      style: TextStyle(
        color: set.textPrimary,
        fontSize: 14,
        fontFamily: kWpUiFont,
        fontFamilyFallback: kWpFontFallback,
      ),
    ),
  );
}

/// The shell in the given colour set, with History active and the dock in its
/// real ready state (local engine loaded, so "Ready locally" and the green dot).
///
/// The hotkey is spelled for macOS whatever the host is, so the board is the
/// same on every machine; the keycap's per-platform spelling has its own test.
///
/// [compactSidebar] mirrors the app below its compact breakpoint, where the
/// sidebar collapses to the icon rail (see `app.dart`, `compactRail`).
Widget appShellBoard(
  WpThemeColors set,
  L10n l10n, {
  bool compactSidebar = false,
}) {
  return Theme(
    data: wpThemeFor(set),
    // The window frame is painted from the frame set, as in the app shell: in
    // the brand set that is the dark palette, not the light background.
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: set.frame.frameGradient),
      child: WpAppShell(
        titleBar: const SizedBox(height: WpLayout.appBarHeight),
        sidebar: WpSidebar(
          compact: compactSidebar,
          items: wpNavItems(l10n),
          dividerAfterIds: wpNavDividerAfterIds,
          activeId: 'history',
          onItemTap: (_) {},
          bottomItems: [wpHelpNavItem(l10n), wpSettingsNavItem(l10n)],
        ),
        contentDecoration: BoxDecoration(color: set.surface),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The page's own inset, as the app's page header gives it.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                WpSpacing.lg,
                WpSpacing.xl,
                WpSpacing.xs,
              ),
              child: WpPageHeader(title: l10n.navHistory),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(set, 'Meeting notes, Monday'),
                  _row(set, 'Draft reply to Maik'),
                  _row(set, 'Shopping list'),
                ],
              ),
            ),
          ],
        ),
        dock: WpRecordingDock(
          smartMode: dockTestSmartMode(
            label: wpSmartModePresetLabel('off', l10n),
          ),
          sttModeLabel: kBoardSttLabel,
          engine: dockTestEngine(label: kBoardSttLabel),
          sttState: SttServerState.ready,
          localProcessing: true,
          hotkeyLabel: formatHotkeyKeycap(
            'meta+shift',
            'D',
            l10n: l10n,
            isMacOS: true,
          ),
        ),
      ),
    ),
  );
}
