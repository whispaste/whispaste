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
///
/// Layout (Ticket 25, decision E10=b): one row per direction, each carrying
/// its whole story on a single line — direction glyph, the remembered path,
/// the action, the chooser. What it replaces was a single "Export / Import
/// Settings" row with both buttons, followed by two separate location lines:
/// the reader had to pair the first button with the first path by position,
/// and four text layers (section title, section subtitle, row label, row
/// subtitle) said the same two things twice. The row label and subtitle are
/// gone; the section header is now the only explanatory prose, which is the
/// shape `review_support_section.dart` and `onboarding_review_section.dart`
/// already have.
///
/// The direction is deliberately carried by the glyph, the action verb and
/// the accessible name rather than by a fourth text layer — a visible
/// "Exportziel" label beside an "Exportieren" button is the very repetition
/// this ticket removes. `settingsPortabilityExportLocationLabel` /
/// `…ImportLocationLabel` live on as the rows' [Semantics] names, so the
/// direction is spoken even though it is not printed.
///
/// Autosicherung (Ticket 26) sits between the two direction rows: below the
/// export it automates, above the import it has nothing to do with. It keeps
/// the same frameless row box the direction rows use rather than a
/// [SettingRow] — the hover surface a [SettingRow] draws says "this whole row
/// is one target", which is as untrue here (a switch *and* a folder chooser)
/// as it is there. Off, the feature costs the section exactly one line: a
/// glyph, the word, a switch. On, its destination and its last run appear,
/// because that is when they mean something.
///
/// The row writes nothing but settings. The runs themselves are driven from
/// the app shell (`app.dart` → `services/settings_autosave_service.dart`),
/// so a snippet edited on another page still triggers a backup with the
/// settings page closed — and so that nothing on this page can reach the
/// background write path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart' show WpIconSize, WpLayout, WpSpacing;
import '../../../features/replacements/replacements_page.dart'
    show replacementsProvider;
import '../../../features/snippets/snippets_page.dart' show snippetsProvider;
import '../../../services/settings_autosave_folder_chooser.dart';
import '../../../services/settings_portability_controller.dart';
import '../../../services/settings_portability_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

/// Row identities of the two direction rows, shared with the widget tests so
/// the structural assertion and the widget cannot drift apart via a typo.
const String kPortabilityExportRowKey = 'portabilityExportRow';
const String kPortabilityImportRowKey = 'portabilityImportRow';

/// Identity of the Autosicherung row and of its passive status line
/// (Ticket 26) — same purpose as the two above.
const String kPortabilityAutosaveRowKey = 'portabilityAutosaveRow';
const String kPortabilityAutosaveStatusKey = 'portabilityAutosaveStatus';

/// Start inset that lines the status line up with the row's text column
/// instead of with its glyph: row inset, glyph, and the gap after it.
const double _autosaveStatusIndent =
    kSettingRowInset + WpIconSize.sm + WpSpacing.sm;

/// Width the location column keeps before the action cluster starts giving
/// way — roughly a truncated directory plus a short file name, i.e. the least
/// that still reads as a path rather than as an ellipsis.
const double _minLocationWidth = 96;

/// Floor under the action cluster, below which the location gives way again.
///
/// Without it the location's reserve is absolute, and on a line short enough
/// the button is squeezed past its own label into an empty pill — a control
/// that has lost the word that says what it does, which is worse than either
/// of the two texts being clipped. The floor keeps enough for the stem of
/// the verb ("Exportie…") next to the chooser's touch target, and from there
/// down the two halves lose room together instead of one losing all of it.
const double _minActionsWidth = WpLayout.minTouchTarget + WpSpacing.xxs + 96;

class SettingsPortabilitySection extends ConsumerWidget {
  const SettingsPortabilitySection({
    super.key,
    @visibleForTesting this.controllerOverride,
    @visibleForTesting this.autosaveFolderChooserOverride,
  });

  /// Test seam: replaces the production-wired
  /// [SettingsPortabilityController] so widget tests can exercise the
  /// choose-location affordance against injected fakes ([PickPathFn] etc.)
  /// without touching real platform channels. Production code never sets
  /// this.
  final SettingsPortabilityController? controllerOverride;

  /// Test seam for the Autosicherung folder dialog — same purpose as
  /// [controllerOverride]. Production code never sets this.
  final SettingsAutosaveFolderChooser? autosaveFolderChooserOverride;

  SettingsAutosaveFolderChooser get _folderChooser =>
      autosaveFolderChooserOverride ?? const SettingsAutosaveFolderChooser();

  SettingsPortabilityController _controller(WidgetRef ref) {
    if (controllerOverride case final override?) return override;
    return SettingsPortabilityController(
      // Same builder the autosave runner uses (see
      // `buildSettingsExportBundle`), so a hand-made export and an automatic
      // one cannot come to disagree about what is portable.
      gather: () async => buildSettingsExportBundle(
        settings: ref.read(settingsProvider).value ?? AppSettings.defaults,
        replacements: ref.read(replacementsProvider).value ?? const [],
        snippets: ref.read(snippetsProvider).value ?? const [],
      ),
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

  /// Flipping the Autosicherung switch on is the one moment in this
  /// feature's life where a dialog may appear — the user just asked for it,
  /// and a rotation folder has to come from somewhere.
  ///
  /// Nothing is persisted until that dialog succeeds, so cancelling leaves
  /// the switch exactly where it was: a control that visibly turns on, opens
  /// a panel and then snaps back is a worse cancel than one that never
  /// moved. Turning it *off* never asks anything, and deliberately keeps the
  /// remembered folder — switching the feature off and on again should not
  /// cost the user a second trip through a file panel.
  Future<void> _setAutosaveEnabled(WidgetRef ref, bool enabled) async {
    final notifier = ref.read(settingsProvider.notifier);
    if (!enabled) {
      await notifier.updateSettings(
        (s) =>
            s.copyWithSections(autosave: s.autosave.copyWith(enabled: false)),
      );
      return;
    }

    final current =
        (ref.read(settingsProvider).value ?? AppSettings.defaults).autosave;
    var folder = current.folder;
    var bookmark = current.bookmark;
    if (folder.isEmpty) {
      final chosen = await _folderChooser.choose();
      if (chosen == null) return;
      folder = chosen.folder;
      bookmark = chosen.bookmark;
    }
    await notifier.updateSettings(
      (s) => s.copyWithSections(
        autosave: s.autosave.copyWith(
          enabled: true,
          folder: folder,
          bookmark: bookmark,
          // A stale failure from a previous configuration must not greet the
          // user on the status line of a feature they just re-armed; the run
          // this enabling kicks off writes the real state within seconds.
          lastError: '',
        ),
      ),
    );
  }

  /// Points the automation at a different folder. Cancelling changes
  /// nothing — same contract as the direction rows' chooser.
  Future<void> _chooseAutosaveFolder(WidgetRef ref) async {
    final current =
        (ref.read(settingsProvider).value ?? AppSettings.defaults).autosave;
    final chosen = await _folderChooser.choose(
      initialDirectory: current.folder.isEmpty ? null : current.folder,
    );
    if (chosen == null) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            autosave: s.autosave.copyWith(
              folder: chosen.folder,
              bookmark: chosen.bookmark,
              lastError: '',
            ),
          ),
        );
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
          _directionRow(context, ref, forExport: true),
          // Ticket 26 (Autosicherung) hangs its toggle row and the passive
          // "letzte Sicherung" timestamp line in exactly this gap: directly
          // below the export row it belongs to, above the import row it does
          // not — as further children of this Column, with neither row
          // itself having to change.
          _autosaveRow(context, ref),
          ?_autosaveStatusLine(context, ref),
          _directionRow(context, ref, forExport: false),
        ],
      ),
    );
  }

  /// One direction — export or import — complete on a single line:
  /// glyph, remembered location, action, chooser.
  ///
  /// Not a [SettingRow]: that row's label column takes a `String`, and the
  /// thing this row leads with is the *path*, which has to be rendered as
  /// two differently-weighted parts (see [_pathDisplay]) and never as one
  /// flat string. The box around it — [kSettingRowInset] horizontally,
  /// `WpSpacing.sm` vertically, [WpLayout.minTouchTarget] minimum height —
  /// is taken from [SettingRow] on purpose so the two line up with every
  /// other settings row above and below. The hover surface is left off: it
  /// signals "this whole row is one target", which is false here — the row
  /// holds two independent controls and a path that is not a control at all.
  Widget _directionRow(
    BuildContext context,
    WidgetRef ref, {
    required bool forExport,
  }) {
    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      // Keyed so a test can assert the one structural promise of this
      // layout — that a direction's path, action and chooser sit inside one
      // row and never drift back into two parallel lists — which is also
      // the promise Ticket 26 has to build on without breaking.
      key: ValueKey(
        forExport ? kPortabilityExportRowKey : kPortabilityImportRowKey,
      ),
      // The direction is not printed anywhere in this row — the glyph and
      // the action verb carry it visually — so it is stated here, and the
      // location text is announced after it.
      label: forExport
          ? l10n.settingsPortabilityExportLocationLabel
          : l10n.settingsPortabilityImportLocationLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WpLayout.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kSettingRowInset,
            vertical: WpSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Which of the two gives way when the line runs short.
              //
              // The action cluster is the wide, inflexible part: a standard
              // 48-dp button is 233 dp for "Exportieren" at text scale 1.3,
              // and German is the widest of the three languages by roughly a
              // factor of two ("Export" measures ~150). Leaving it unbounded
              // is what overflows a 280-dp line, and letting the *path* take
              // the whole squeeze instead would leave a location column with
              // nothing but an ellipsis in it — a path that says nothing is
              // worse than a verb that ellipsizes, because the verb is also
              // written on the tooltip and in the section header.
              //
              // So the location keeps [_minLocationWidth] and the cluster is
              // capped at whatever is left. At the real floor of the settings
              // column — ~680 dp inside an 800-dp minimum window — the cap
              // sits far above the cluster's natural width and changes
              // nothing; it engages only in layouts narrower than the page
              // can actually be, which is where the ticket's 280-dp check
              // lives.
              final actionsCap =
                  constraints.maxWidth -
                  (WpIconSize.sm + WpSpacing.sm + WpSpacing.sm) -
                  _minLocationWidth;
              return Row(
                children: [
                  // `upload`/`download`, not `fileUp`/`fileDown`. The file
                  // pair is the better metaphor on paper — what happens here
                  // is a file on this machine, not a transfer to a service —
                  // but at [WpIconSize.sm] it does not survive rendering: the
                  // arrow is a ~6-dp detail inside a document outline, so
                  // both glyphs read as the same blank page and the row
                  // carries no direction at all. That is only invisible in
                  // the state where the two paths differ; set both to the
                  // same file (export here, import from the same backup —
                  // the ordinary round trip) and the rows become
                  // indistinguishable except for the button verb. These
                  // glyphs spend their whole box on the arrow, so the
                  // direction survives at 16 dp.
                  Icon(
                    forExport ? LucideIcons.upload : LucideIcons.download,
                    size: WpIconSize.sm,
                    color: cs.secondary,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Expanded(child: _locationDisplay(context, ref, forExport)),
                  const SizedBox(width: WpSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: actionsCap < _minActionsWidth
                          ? _minActionsWidth
                          : actionsCap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: WpButton(
                            label: forExport
                                ? l10n.settingsPortabilityExportAction
                                : l10n.settingsPortabilityImportAction,
                            variant: WpButtonVariant.secondary,
                            onPressed: forExport
                                ? () => _controller(ref).export(context)
                                : () => _confirmImport(context, ref),
                          ),
                        ),
                        const SizedBox(width: WpSpacing.xxs),
                        IconButton(
                          icon: Icon(
                            LucideIcons.folderPen,
                            size: WpIconSize.sm,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? WpColors.textMuted
                                : WpColors.textMuted,
                          ),
                          // The tooltip does double duty: it names the
                          // icon-only affordance (all three languages) and
                          // states explicitly that choosing only sets the
                          // location — nothing is exported/imported by it.
                          // With the chooser now standing next to the action
                          // instead of a line below it, that separation is
                          // carried by rank — a muted 16-px glyph against an
                          // outlined button — and by this sentence.
                          tooltip: forExport
                              ? l10n.settingsPortabilityChooseExportLocation
                              : l10n.settingsPortabilityChooseImportLocation,
                          onPressed: () => _controller(
                            ref,
                          ).chooseNewLocation(forExport: forExport),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: WpLayout.minTouchTarget,
                            minHeight: WpLayout.minTouchTarget,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Autosicherung on one line: glyph, name, the switch, and — once it is on
  /// — where it writes and how to move that.
  ///
  /// Off is the default and the quiet state: no path, no chooser, nothing to
  /// read. A destination the automation is not using would be furniture, and
  /// this section's whole point (Ticket 25) was to stop saying things twice.
  /// The glyph is the recurrence glyph rather than a third arrow: direction
  /// is already settled by the row sitting under the export it automates,
  /// and what this row adds to it is "by itself, again and again".
  Widget _autosaveRow(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const muted = WpColors.textMuted;

    final autosave =
        ref.watch(settingsProvider).value?.autosave ??
        AppSettings.defaults.autosave;
    final enabled = autosave.enabled;

    return Semantics(
      key: const ValueKey(kPortabilityAutosaveRowKey),
      // Unlike the direction rows, this row's name *is* printed — so it is
      // stated once here and excluded from the rendered text below, the
      // arrangement [SettingRow] settled on. Announcing the switch's state
      // is what `toggled` is for; the folder path stays in the tree and is
      // read after the name.
      label: l10n.settingsAutosaveLabel,
      hint: l10n.settingsAutosaveHint,
      toggled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WpLayout.minTouchTarget),
        child: Padding(
          // Bottom inset tightens when the status line follows, so the line
          // reads as this row's caption rather than as a fourth entry in the
          // section's list.
          padding: EdgeInsets.fromLTRB(
            kSettingRowInset,
            WpSpacing.sm,
            kSettingRowInset,
            enabled ? WpSpacing.xxs : WpSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: WpIconSize.sm,
                color: cs.secondary,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        l10n.settingsAutosaveLabel,
                        style: tt.bodyLarge,
                      ),
                    ),
                    if (enabled && autosave.folder.isNotEmpty)
                      Padding(
                        // Same 2-px title/subtitle gap [SettingRow] uses, so
                        // the pair reads as one unit.
                        padding: const EdgeInsets.only(top: 2),
                        // Both halves muted: this is a caption under a name,
                        // not the row's leading content the way a path is on
                        // the direction rows. What [_pathDisplay] still buys
                        // here is the truncation side — the folder's own name
                        // survives, the directory above it gives way.
                        child: _pathDisplay(
                          autosave.folder,
                          dirStyle: tt.bodySmall?.copyWith(color: muted),
                          baseStyle: tt.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  settingsToggle(
                    value: enabled,
                    onChanged: (value) => _setAutosaveEnabled(ref, value),
                  ),
                  if (enabled) ...[
                    const SizedBox(width: WpSpacing.xxs),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.folderPen,
                        size: WpIconSize.sm,
                        color: muted,
                      ),
                      tooltip: l10n.settingsAutosaveChooseFolder,
                      onPressed: () => _chooseAutosaveFolder(ref),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: WpLayout.minTouchTarget,
                        minHeight: WpLayout.minTouchTarget,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The passive "Letzte Sicherung: …" line (decision E11d) — the only place
  /// in the app that reports on autosave runs at rest. Never the status bar:
  /// the maintainer ruled that out explicitly, and a permanent readout of a
  /// thing that succeeded is exactly the interruption a silent backup is
  /// supposed to avoid.
  ///
  /// `null` while the feature is off, so an unused feature costs the section
  /// no line at all. A failure never renders as a success: with an earlier
  /// good backup it says so *and* keeps the timestamp, without one it only
  /// reports the failure. The toast carries the failure at the moment it
  /// happens; this line is what is still there tomorrow.
  Widget? _autosaveStatusLine(BuildContext context, WidgetRef ref) {
    final autosave =
        ref.watch(settingsProvider).value?.autosave ??
        AppSettings.defaults.autosave;
    if (!autosave.enabled) return null;

    final l10n = L10n.of(context);
    final tt = Theme.of(context).textTheme;

    final failed = autosave.lastError.isNotEmpty;
    final lastSuccess = DateTime.tryParse(autosave.lastSuccess)?.toLocal();
    final stamp = lastSuccess == null
        ? null
        : DateFormat.yMd(
            Localizations.localeOf(context).toString(),
          ).add_Hm().format(lastSuccess);

    final message = switch ((failed, stamp)) {
      (true, final at?) => l10n.settingsAutosaveLastRunFailedSince(at),
      (true, null) => l10n.settingsAutosaveLastRunFailed,
      (false, final at?) => l10n.settingsAutosaveLastRun(at),
      (false, null) => l10n.settingsAutosaveNeverRun,
    };

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        _autosaveStatusIndent,
        0,
        kSettingRowInset,
        WpSpacing.sm,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          message,
          key: const ValueKey(kPortabilityAutosaveStatusKey),
          style: tt.bodySmall?.copyWith(
            color: failed ? (WpColors.warning) : (WpColors.textMuted),
          ),
          // Two lines, unlike every other text in this section: the
          // timestamp sits at the *end* of the sentence ("Letzter Versuch
          // fehlgeschlagen – letzte Sicherung: …"), so a one-line ellipsis
          // would cut away the one thing this line exists to show. A path
          // can lose its middle and stay useful; this cannot.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// The remembered location of one direction, or the honest "asked on
  /// first export/import" state — never an invented suggestion the user did
  /// not confirm.
  ///
  /// This is the row's leading content, so it takes the size a [SettingRow]
  /// label would have — `bodyLarge`, for the whole path — and separates its
  /// two halves by colour alone: `textPrimary` for the basename, which is
  /// what names the backup, `textMuted` for the directory, which is only
  /// where it sits. Colour rather than size because a path is one string:
  /// setting the directory a point smaller put a visible step mid-word right
  /// where the truncation ellipsis already sits, and the two artefacts read
  /// together as a rendering fault. The unset state stays muted throughout —
  /// an absence should not read as loudly as a chosen file.
  Widget _locationDisplay(BuildContext context, WidgetRef ref, bool forExport) {
    final l10n = L10n.of(context);
    final tt = Theme.of(context).textTheme;
    const muted = WpColors.textMuted;
    const primary = WpColors.textPrimary;

    // Read for display only — never `resolvePath()`, which would open the
    // native file dialog while merely rendering the settings page. Watched
    // so a newly chosen location re-renders immediately.
    final paths =
        ref.watch(settingsProvider).value?.portabilityPaths ??
        AppSettings.defaults.portabilityPaths;
    final path = forExport ? paths.exportPath : paths.importPath;
    final mutedStyle = tt.bodyLarge?.copyWith(color: muted);

    return Align(
      // Resolved against the ambient (locale) direction, so the path hugs
      // the reading start next to its glyph in LTR and RTL alike.
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
              baseStyle: tt.bodyLarge?.copyWith(color: primary),
            ),
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
            // Hung from the shared baseline rather than centred: the two
            // halves are one path and must sit on one line even if a caller
            // ever hands them differently-sized styles.
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
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
