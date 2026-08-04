/// Settings portability (dateibasierter Export/Import) as its own top-level
/// settings section — the full portable settings state (deny-list-filtered
/// `AppSettings.toStorageMap()`), Text Replacements, and Snippets. See
/// `services/settings_portability_service.dart` for the deny list and the
/// `mergeImportedSettings` merge seam, and
/// `services/settings_portability_controller.dart` for the path/toast
/// contract; this section wires the two buttons + the destructive-ish
/// import confirm, and (Ticket 05) shows the remembered export/import
/// location per direction with a "choose another location" affordance.
///
/// The remembered locations are read straight from
/// `AppSettings.portabilityPaths` — never via `resolvePath()`, which would
/// pop the native file dialog just for rendering the settings page. An
/// empty string simply means "no location remembered yet".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart' show WpIconSize, WpLayout, WpSpacing;
import '../../../features/replacements/replacements_page.dart'
    show replacementsProvider;
import '../../../features/snippets/snippets_page.dart' show snippetsProvider;
import '../../../services/settings_portability_controller.dart';
import '../../../services/settings_portability_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class SettingsPortabilitySection extends ConsumerWidget {
  const SettingsPortabilitySection({
    super.key,
    @visibleForTesting this.controllerOverride,
  });

  /// Test seam: replaces the production-wired
  /// [SettingsPortabilityController] so widget tests can exercise the
  /// choose-location affordance against injected fakes ([PickPathFn] etc.)
  /// without touching real platform channels. Production code never sets
  /// this.
  final SettingsPortabilityController? controllerOverride;

  SettingsPortabilityController _controller(WidgetRef ref) {
    if (controllerOverride case final override?) return override;
    return SettingsPortabilityController(
      gather: () async {
        final settings =
            ref.read(settingsProvider).value ?? AppSettings.defaults;
        final replacements = ref.read(replacementsProvider).value ?? const [];
        final snippets = ref.read(snippetsProvider).value ?? const [];
        // Filtered here at the source *and* again in
        // `SettingsPortabilityService.encode` (the file-writing boundary,
        // which cannot assume its caller filtered) — deliberate, not
        // accidental duplication. This matters for the machine-bound keys
        // (window geometry, onboarding progress, microphone) that carry
        // real values here; the two API-key entries are moot either way,
        // since `CloudProviderSettings.toMap()` always writes them as ''
        // regardless of filtering (secure storage is the real API-key
        // guard — see `mergeImportedSettings`).
        final filteredSettings = <String, String>{
          for (final entry in settings.toStorageMap().entries)
            if (!settingsPortabilityDenyList.contains(entry.key))
              entry.key: entry.value,
        };
        return SettingsExportBundle(
          settings: filteredSettings,
          replacements: replacements,
          snippets: snippets,
        );
      },
      apply: (bundle) async {
        await ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => mergeImportedSettings(s, bundle.settings));
        await ref
            .read(replacementsProvider.notifier)
            .replaceAll(bundle.replacements);
        // `bundle.snippets` is `null` when the import file predates the
        // Snippets feature (no "snippets" key) — leave the user's existing
        // snippets untouched rather than silently clearing them.
        if (bundle.snippets case final snippets?) {
          await ref.read(snippetsProvider.notifier).replaceAll(snippets);
        }
      },
      getExportPath: () async =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .portabilityPaths
              .exportPath,
      setExportPath: (path) => ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              portabilityPaths: s.portabilityPaths.copyWith(exportPath: path),
            ),
          ),
      getImportPath: () async =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .portabilityPaths
              .importPath,
      setImportPath: (path) => ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              portabilityPaths: s.portabilityPaths.copyWith(importPath: path),
            ),
          ),
      getExportBookmark: () async =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .portabilityPaths
              .exportBookmark,
      setExportBookmark: (bookmark) => ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              portabilityPaths: s.portabilityPaths.copyWith(
                exportBookmark: bookmark,
              ),
            ),
          ),
      getImportBookmark: () async =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .portabilityPaths
              .importBookmark,
      setImportBookmark: (bookmark) => ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              portabilityPaths: s.portabilityPaths.copyWith(
                importBookmark: bookmark,
              ),
            ),
          ),
    );
  }

  Future<void> _confirmImport(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final controller = _controller(ref);
    // Resolves the remembered import path, or opens the native open-file
    // dialog once — cancelling it aborts here silently (no confirm dialog,
    // no toast). `controller.import()` below re-resolves the same
    // now-remembered path without prompting again.
    final path = await controller.resolvePath(forExport: false);
    if (path == null) return;
    if (!context.mounted) return;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsPortabilityImportConfirmTitle,
      message: l10n.settingsPortabilityImportConfirmMessage(path),
      confirmLabel: l10n.settingsPortabilityImportAction,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    await controller.import(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpSection(
      title: l10n.settingsPortabilitySectionTitle,
      subtitle: l10n.settingsPortabilitySectionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingRow(
            icon: LucideIcons.arrowUpDown,
            label: l10n.settingsPortabilityLabel,
            subtitle: l10n.settingsPortabilitySubtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => _controller(ref).export(context),
                  child: Text(l10n.settingsPortabilityExportAction),
                ),
                const SizedBox(width: WpSpacing.sm),
                OutlinedButton(
                  onPressed: () => _confirmImport(context, ref),
                  child: Text(l10n.settingsPortabilityImportAction),
                ),
              ],
            ),
          ),
          // Remembered-location lines (Ticket 05), indented to the
          // SettingRow label column (row padding + icon + gap). The
          // choose-location affordance lives here, next to the path it
          // changes — physically apart from the Export/Import buttons
          // above, so it cannot be mistaken for the main action.
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: WpSpacing.sm + WpIconSize.sm + WpSpacing.sm,
              end: WpSpacing.sm,
              bottom: WpSpacing.xxs,
            ),
            child: Column(
              children: [
                _locationLine(context, ref, forExport: true),
                _locationLine(context, ref, forExport: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One remembered-location line: direction label, the remembered path
  /// (or the honest "asked on first export/import" state — never an
  /// invented suggestion the user did not confirm), and the icon-button
  /// that picks a new location via [SettingsPortabilityController.chooseNewLocation]
  /// — the same dialog path export/import use internally, which only sets
  /// the location and never writes or imports anything. Cancelling it
  /// leaves the remembered location untouched.
  Widget _locationLine(
    BuildContext context,
    WidgetRef ref, {
    required bool forExport,
  }) {
    final l10n = L10n.of(context);
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final secondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    // Read for display only — never `resolvePath()`, which would open the
    // native file dialog while merely rendering the settings page. Watched
    // so a newly chosen location re-renders immediately.
    final paths =
        ref.watch(settingsProvider).value?.portabilityPaths ??
        AppSettings.defaults.portabilityPaths;
    final path = forExport ? paths.exportPath : paths.importPath;
    final mutedStyle = tt.bodySmall?.copyWith(color: muted);

    return Row(
      children: [
        Text(
          forExport
              ? l10n.settingsPortabilityExportLocationLabel
              : l10n.settingsPortabilityImportLocationLabel,
          style: mutedStyle,
        ),
        const SizedBox(width: WpSpacing.sm),
        Expanded(
          child: Align(
            // Resolved against the ambient (locale) direction, so the path
            // hugs the reading start next to its label in LTR and RTL alike.
            alignment: AlignmentDirectional.centerStart,
            child: path.isEmpty
                ? Text(
                    forExport
                        ? l10n.settingsPortabilityExportLocationUnset
                        : l10n.settingsPortabilityImportLocationUnset,
                    style: mutedStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : _pathDisplay(
                    path,
                    dirStyle: mutedStyle,
                    baseStyle: tt.bodySmall?.copyWith(color: secondary),
                  ),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        IconButton(
          icon: Icon(LucideIcons.folderPen, size: WpIconSize.sm, color: muted),
          // The tooltip does double duty: it names the icon-only affordance
          // (all three languages) and states explicitly that choosing only
          // sets the location — nothing is exported/imported by it.
          tooltip: forExport
              ? l10n.settingsPortabilityChooseExportLocation
              : l10n.settingsPortabilityChooseImportLocation,
          onPressed: () =>
              _controller(ref).chooseNewLocation(forExport: forExport),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: WpLayout.minTouchTarget,
            minHeight: WpLayout.minTouchTarget,
          ),
        ),
      ],
    );
  }

  /// Renders [path] on a single line without ever hiding its most
  /// informative part: the directory prefix ellipsizes ("…" — a visible
  /// truncation marker), the basename always stays intact, and the full
  /// path remains reachable via tooltip. Forced LTR because filesystem
  /// paths are inherently left-to-right data, also under the Hebrew RTL
  /// locale — which is exactly what keeps the truncation on the correct
  /// (directory) side there too.
  Widget _pathDisplay(
    String path, {
    TextStyle? dirStyle,
    TextStyle? baseStyle,
  }) {
    final dir = p.dirname(path);
    final dirWithSep = dir.endsWith(p.separator) ? dir : '$dir${p.separator}';
    return Tooltip(
      message: path,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          // The basename may claim up to the full line (ellipsizing only in
          // the pathological long-filename case); the directory part gets
          // whatever remains. Plain two-Flexible sharing would wrongly
          // truncate the directory at half width even when the basename is
          // short — Flex never redistributes unused flexible space.
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  dirWithSep,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: dirStyle,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Text(
                  p.basename(path),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
