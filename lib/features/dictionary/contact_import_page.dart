import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/contact_names.dart';
import '../../services/dictionary/gnome_contact_source.dart';
import '../../services/dictionary/kde_contact_source.dart';
import '../../services/dictionary/macos_contact_source.dart';
import '../../services/dictionary/outlook_contact_source.dart';
import '../../services/dictionary/system_contact_source.dart';
import '../../services/dictionary/term_import.dart';
import '../../services/dictionary/windows_contact_source.dart';
import '../../widgets/dialog.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_page_header.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../replacements/replacements_page.dart';

final _log = AppLogger('ContactImportPage');

const _contactTypes = XTypeGroup(
  label: 'vCard / CSV',
  extensions: ['vcf', 'vcard', 'csv'],
  uniformTypeIdentifiers: [
    'public.vcard',
    'public.comma-separated-values-text',
  ],
);

Future<void> openContactImport(BuildContext context, {XFile? file}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ContactImportPage(file: file)),
    );

/// Contact names into the dictionary (#2036): a vCard or CSV export becomes
/// a reviewed suggestion list, never a bulk import. The names of one file
/// form a group that a later file updates (new and dropped names shown for
/// confirmation) and that is removed in one step, which also withdraws the
/// consent for that source.
///
/// The system address books are further sources: Windows contacts (#2038),
/// macOS contacts (#2037); on Linux the GNOME contacts through Evolution
/// Data Server (#2040) and the KDE address book through Akonadi (#2041),
/// each with its own read button when it is there. A read builds the same
/// reviewed list, and opening the page again compares each system group with
/// its address book and shows the changes for confirmation. On macOS the
/// page explains the read before the system asks for access, and the
/// comparison on opening never brings up that prompt. Address books are read
/// only here, never on the hotkey path. Where a sandbox keeps one out of
/// reach (Flatpak, Snap), the page explains the vCard export instead.
///
/// Also on Windows, the local classic Outlook is a further source (#2039):
/// "Read Outlook contacts" builds the same list from the running Outlook;
/// it is compared again only on "Update", never when the page opens, so the
/// page never reaches into Outlook unasked.
class ContactImportPage extends ConsumerStatefulWidget {
  const ContactImportPage({super.key, this.file});
  final XFile? file;

  @override
  ConsumerState<ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends ConsumerState<ContactImportPage> {
  List<ContactNameGroup> _groups = const [];

  /// The group the current file updates; `null` for a new source.
  ContactNameGroup? _target;

  /// Kind and label of the source of [_candidates] (`file` or the kind of
  /// the system source).
  String _kind = 'file';
  String? _label;
  List<String>? _candidates;
  final Set<int> _excluded = {};
  bool _busy = false;
  String? _message;
  bool _failed = false;

  /// Why the system address book could not be read; offers the privacy
  /// settings when access is refused.
  ContactSourceFailure? _failure;

  /// The privacy setting of the source whose read [_failure] refused.
  Uri? _failureSettings;

  /// The system address books of this platform.
  late final List<SystemContactSource> _systems = ref.read(
    systemContactSourcesProvider,
  );

  /// Whether the page offers each of [_systems], by kind; missing until
  /// checked.
  final Map<String, SystemContactsAvailability> _availability = {};

  @override
  void initState() {
    super.initState();
    final loaded = _loadGroups();
    if (widget.file != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _read(dropped: widget.file);
      });
    }
    _checkSystem(loaded, compare: widget.file == null);
  }

  /// Which system address books are there; with [compare], compares each
  /// one the user agreed to with its group, until one shows changes.
  Future<void> _checkSystem(
    Future<void> loaded, {
    required bool compare,
  }) async {
    final checks = await Future.wait([
      for (final system in _systems)
        system.availability().then<SystemContactsAvailability?>(
          (a) => a,
          onError: (Object _) => null,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      for (final (i, availability) in checks.indexed) {
        if (availability != null) {
          _availability[_systems[i].kind] = availability;
        }
      }
    });
    await loaded;
    for (final system in _systems) {
      if (!mounted || !compare || _candidates != null) return;
      if (_readable(system) &&
          !_readOnClickOnly.contains(system.kind) &&
          _groupOf(system.kind) != null) {
        await _readSystem(system, onOpen: true);
      }
    }
  }

  bool _readable(SystemContactSource source) =>
      _availability[source.kind] == SystemContactsAvailability.available;

  /// The group of the system address book [kind], if the user agreed to it.
  ContactNameGroup? _groupOf(String kind) {
    for (final g in _groups) {
      if (g.sourceKind == kind) return g;
    }
    return null;
  }

  /// The system address book of [kind], if this platform has it.
  SystemContactSource? _systemOf(String kind) {
    for (final s in _systems) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  /// Reads the system address book [source]. Without a group this is a new
  /// source; with one, an update of it. [onOpen] is the comparison when the
  /// page opens: it shows the list only when names came or went, and never
  /// makes the system ask for access. An explicit read that would bring up
  /// that prompt first explains it and waits for the user's go.
  Future<void> _readSystem(
    SystemContactSource source, {
    bool onOpen = false,
  }) async {
    if (!_readable(source) || _busy) return;
    final l10n = L10n.of(context);
    final target = _groupOf(source.kind);
    setState(() => _busy = true);
    try {
      final List<String> candidates;
      if (onOpen) {
        final read = await readSystemContactsOnOpen(source);
        if (read == null) return;
        candidates = read;
      } else {
        if (await source.asksForAccess()) {
          if (!mounted) return;
          final go = await showWpConfirmDialog(
            context: context,
            title: l10n.dictionaryContactsMacAccessTitle,
            message: l10n.dictionaryContactsMacAccessMessage,
            confirmLabel: l10n.dictionaryContactsMacAccessConfirm,
            cancelLabel: l10n.actionCancel,
          );
          if (!go) return;
        }
        candidates = contactNameCandidates(await source.read());
      }
      if (!mounted) return;
      if (onOpen) {
        // A file picked or dropped meanwhile wins.
        if (_candidates != null || target == null) return;
        final rows = planContactImport(
          candidates,
          _planEntries(await ref.read(replacementsProvider.future)),
          groupId: target.id,
        );
        if (!contactImportHasChanges(rows)) return;
      }
      if (!mounted) return;
      setState(() {
        _target = target;
        _kind = source.kind;
        _label = source.label;
        _candidates = candidates;
        _excluded.clear();
        final texts = _SystemTexts.of(l10n, source.kind)!;
        _message = onOpen
            ? texts.changed
            : candidates.isEmpty && target == null
            ? texts.empty
            : null;
        _failed = false;
        _failure = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      final failure = error is ContactSourceException
          ? error.reason
          : ContactSourceFailure.unavailable;
      setState(() {
        if (!onOpen) _candidates = null;
        _message = _SystemTexts.of(l10n, source.kind)!.failure(failure);
        _failure = failure;
        _failureSettings = source.settingsUri;
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPrivacySettings() async {
    final uri = _failureSettings;
    if (uri == null) return;
    try {
      await launchUrl(uri);
    } on Object catch (e) {
      // Nothing to add: the hint names the settings path.
      _log.debug('Privacy settings not opened', e);
    }
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await ref
          .read(historyDatabaseProvider)
          .readContactNameGroups();
      if (mounted) setState(() => _groups = groups);
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = null;
          _message = L10n.of(context).errorGeneric;
        });
      }
    }
  }

  Future<void> _read({XFile? dropped, ContactNameGroup? target}) async {
    if (_busy) return;
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      final file =
          dropped ?? await openFile(acceptedTypeGroups: const [_contactTypes]);
      if (file == null) return;
      final source = ContactFileSource(
        label: file.name,
        bytes: () => _bytes(file),
      );
      final candidates = contactNameCandidates(await source.read());
      if (!mounted) return;
      setState(() {
        _target = target;
        _kind = source.kind;
        _label = source.label;
        _candidates = candidates;
        _excluded.clear();
        _message = candidates.isEmpty && target == null
            ? l10n.dictionaryContactsNone
            : null;
        _failed = false;
        _failure = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _candidates = null;
        _message = l10n.dictionaryContactsError;
        _failed = true;
        _failure = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<Uint8List> _bytes(XFile file) async {
    final bookmark = file is DropItem ? file.extraAppleBookmark : null;
    final scoped =
        bookmark != null &&
        bookmark.isNotEmpty &&
        await DesktopDrop.instance.startAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
    try {
      if (await file.length() > termImportMaxBytes) {
        throw const FormatException('size');
      }
      return await file.readAsBytes();
    } finally {
      if (scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  static List<ContactPlanEntry> _planEntries(List<Replacement> entries) => [
    for (final r in entries)
      (
        id: r.id,
        triggers: r.triggers,
        replacement: r.replacement,
        importGroupId: r.importGroupId,
      ),
  ];

  List<ContactImportRow> _plan(List<Replacement> entries) => planContactImport(
    _candidates ?? const [],
    _planEntries(entries),
    groupId: _target?.id,
  );

  Future<void> _confirm() async {
    if (_busy) return;
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      // Planned again against the current dictionary, so an entry added or
      // edited meanwhile is neither duplicated nor removed.
      final rows = _plan(await ref.read(replacementsProvider.future));
      final changes = contactImportChanges(rows, _excluded);
      final add = [
        for (final name in changes.add) (id: generateV4Uuid(), name: name),
      ];
      final remove = changes.removeIds;
      final target = _target;
      final now = DateTime.now();
      await ref
          .read(historyDatabaseProvider)
          .applyContactNameImport(
            groupId: target?.id ?? generateV4Uuid(),
            sourceKind: _kind,
            sourceLabel: _label ?? '',
            consentedAt: target?.consentedAt ?? now,
            add: add,
            removeIds: remove,
            now: now,
          );
      await ref.read(replacementsProvider.notifier).reload();
      await _loadGroups();
      if (!mounted) return;
      setState(() {
        _message = l10n.dictionaryContactsResult(add.length, remove.length);
        _failed = false;
        _failure = null;
        _candidates = null;
        _target = null;
        _excluded.clear();
      });
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = null;
          _message = l10n.errorGeneric;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ContactNameGroup group, int count) async {
    if (_busy) return;
    final l10n = L10n.of(context);
    final ok = await showWpConfirmDialog(
      context: context,
      title: l10n.dictionaryContactsRemoveTitle,
      message: l10n.dictionaryContactsRemoveMessage(
        count,
        _sourceName(l10n, group),
      ),
      confirmLabel: l10n.dictionaryContactsRemove,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(historyDatabaseProvider).deleteContactNameGroup(group.id);
      await ref.read(replacementsProvider.notifier).reload();
      await _loadGroups();
      if (!mounted) return;
      setState(() {
        if (_target?.id == group.id) {
          _target = null;
          _candidates = null;
        }
        _message = l10n.dictionaryContactsRemoved(count);
        _failed = false;
        _failure = null;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = null;
          _message = l10n.errorGeneric;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final replacements = ref.watch(replacementsProvider);
    final entries = replacements.value ?? const <Replacement>[];
    final ready = replacements.hasValue && !replacements.hasError;
    final rows = _plan(entries);
    var adding = 0;
    var removing = 0;
    for (var i = 0; i < rows.length; i++) {
      if (_excluded.contains(i)) continue;
      if (rows[i].status == ContactImportStatus.fresh) adding++;
      if (rows[i].status == ContactImportStatus.dropped) removing++;
    }
    final target = _target;
    // The texts of the system address book the list comes from, if any.
    final systemTexts = _kind == 'file' ? null : _SystemTexts.of(l10n, _kind);
    return Scaffold(
      body: Semantics(
        identifier: 'dictionary-contacts-page',
        child: DropTarget(
          onDragDone: (details) {
            if (_busy) return;
            if (details.files.length == 1) {
              // A file updates a file group only, never the system one.
              _read(
                dropped: details.files.single,
                target: _kind == 'file' ? _target : null,
              );
            } else {
              setState(() {
                _candidates = null;
                _message = l10n.dictionaryContactsError;
                _failed = true;
                _failure = null;
              });
            }
          },
          child: WpPageShell(
            scrollable: false,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WpPageHeader(title: l10n.dictionaryContactsTitle),
                const SizedBox(height: WpSpacing.sm),
                Text(l10n.dictionaryContactsHint),
                const SizedBox(height: WpSpacing.sm),
                for (final (index, group) in _groups.indexed)
                  _GroupRow(
                    index: index,
                    group: group,
                    name: _sourceName(l10n, group),
                    count: entries
                        .where((r) => r.importGroupId == group.id)
                        .length,
                    busy: _busy,
                    // A system group updates from its address book only;
                    // without access (another build) it can only be removed.
                    onUpdate: group.sourceKind == 'file'
                        ? () => _read(target: group)
                        : switch (_systemOf(group.sourceKind)) {
                            final system? when _readable(system) =>
                              () => _readSystem(system),
                            _ => null,
                          },
                    onRemove: (count) => _remove(group, count),
                  ),
                if (target != null && _candidates != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WpSpacing.sm),
                    child: Text(
                      systemTexts?.updating ??
                          l10n.dictionaryContactsUpdating(
                            _sourceName(l10n, target),
                          ),
                    ),
                  ),
                Wrap(
                  spacing: WpSpacing.buttonGap,
                  runSpacing: WpSpacing.sm,
                  children: [
                    for (final system in _systems)
                      if (_readable(system))
                        WpButton(
                          testId: 'dictionary-contacts-${system.kind}',
                          variant: WpButtonVariant.secondary,
                          label: _SystemTexts.of(l10n, system.kind)!.read,
                          onPressed: _busy ? null : () => _readSystem(system),
                        ),
                    WpButton(
                      testId: 'dictionary-contacts-pick',
                      variant: WpButtonVariant.secondary,
                      label: l10n.dictionaryContactsPick,
                      onPressed: _busy ? null : () => _read(),
                    ),
                    WpButton(
                      testId: 'dictionary-contacts-confirm',
                      variant: WpButtonVariant.primary,
                      label: target == null
                          ? l10n.dictionaryContactsConfirmNew(adding)
                          : l10n.dictionaryContactsConfirmUpdate(
                              adding,
                              removing,
                            ),
                      onPressed:
                          !_busy &&
                              ready &&
                              _candidates != null &&
                              adding + removing > 0
                          ? _confirm
                          : null,
                    ),
                    WpButton(
                      testId: 'dictionary-contacts-close',
                      label: l10n.actionClose,
                      variant: WpButtonVariant.ghost,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                for (final system in _systems)
                  if (_SystemTexts.of(l10n, system.kind)?.sandboxed
                      case final sandboxed?
                      when _availability[system.kind] ==
                          SystemContactsAvailability.sandboxed)
                    Semantics(
                      identifier:
                          'dictionary-contacts-${system.kind}-sandboxed',
                      child: Padding(
                        padding: const EdgeInsets.only(top: WpSpacing.sm),
                        child: Text(sandboxed),
                      ),
                    ),
                if (_candidates != null && target == null)
                  Padding(
                    padding: const EdgeInsets.only(top: WpSpacing.sm),
                    child: Text(l10n.dictionaryContactsConsent),
                  ),
                if (_message != null)
                  WpBanner(
                    message: _message!,
                    tone: _failed ? WpBannerTone.error : WpBannerTone.info,
                    action:
                        _failure == ContactSourceFailure.denied &&
                            _failureSettings != null
                        ? WpButton(
                            testId: 'dictionary-contacts-system-settings',
                            label: l10n.dictionaryContactsOpenSettings,
                            variant: WpButtonVariant.secondary,
                            size: WpButtonSize.dense,
                            onPressed: _openPrivacySettings,
                          )
                        : null,
                  ),
                if (replacements.hasError)
                  WpBanner(
                    message: l10n.errorGeneric,
                    tone: WpBannerTone.error,
                  ),
              ],
            ),
            child: ListView.builder(
              key: const ValueKey('dictionary-contacts-preview'),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final status = switch (row.status) {
                  ContactImportStatus.fresh => l10n.dictionaryTermImportNew,
                  ContactImportStatus.existing =>
                    l10n.dictionaryContactsExisting,
                  ContactImportStatus.kept => l10n.dictionaryContactsKept,
                  ContactImportStatus.dropped =>
                    systemTexts?.dropped ?? l10n.dictionaryContactsDropped,
                };
                return Semantics(
                  identifier: 'dictionary-contacts-row-$i',
                  child: Row(
                    children: [
                      if (row.selectable)
                        Semantics(
                          identifier: 'dictionary-contacts-select-$i',
                          child: WpRowCheckbox(
                            key: ValueKey('dictionary-contacts-select-$i'),
                            value: !_excluded.contains(i),
                            semanticsLabel: row.name,
                            onChanged: () {
                              if (!_busy) {
                                setState(() {
                                  if (!_excluded.add(i)) _excluded.remove(i);
                                });
                              }
                            },
                          ),
                        )
                      else
                        const SizedBox(width: WpRowCheckbox.extent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: WpSpacing.sm,
                          ),
                          child: Text('${row.name} — $status'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// What the user recognises [group] by: the file name, or the localized
/// name of the system address book.
String _sourceName(L10n l10n, ContactNameGroup group) =>
    group.sourceKind == 'file'
    ? group.sourceLabel
    : _SystemTexts.of(l10n, group.sourceKind)?.source ?? group.sourceLabel;

/// System address books read on a click only, never compared when the page
/// opens: reading Outlook (#2039) needs it open and may stall on one of its
/// dialogs, so the page never reaches into it unasked.
const Set<String> _readOnClickOnly = {kOutlookContactsKind};

/// The texts of one system address book.
class _SystemTexts {
  const _SystemTexts({
    required this.read,
    required this.source,
    this.changed,
    required this.dropped,
    required this.empty,
    required this.tooMany,
    required this.unavailable,
    required this.updating,
    this.denied,
    this.restricted,
    this.unpackaged,
    this.notInstalled,
    this.notRunning,
    this.busy,
    this.sandboxed,
  });

  final String read;
  final String source;

  /// Shown when the page opens and the address book changed; `null` for the
  /// ones in [_readOnClickOnly].
  final String? changed;
  final String dropped;
  final String empty;
  final String tooMany;
  final String unavailable;
  final String updating;

  /// Why access is refused, by policy, or (Windows) for want of the package
  /// identity; a source without such a case falls back to [unavailable].
  final String? denied;
  final String? restricted;
  final String? unpackaged;

  /// Outlook (#2039): not installed (or only the new Outlook), not open, or
  /// stalled on one of its dialogs; the other sources fall back to
  /// [unavailable].
  final String? notInstalled;
  final String? notRunning;
  final String? busy;

  /// Why a sandboxed build cannot read it, with the file export as the way.
  final String? sandboxed;

  static _SystemTexts? of(L10n l10n, String kind) => switch (kind) {
    kWindowsContactsKind => _SystemTexts(
      read: l10n.dictionaryContactsWindowsRead,
      source: l10n.dictionaryContactsWindowsSource,
      changed: l10n.dictionaryContactsWindowsChanged,
      dropped: l10n.dictionaryContactsWindowsDropped,
      empty: l10n.dictionaryContactsWindowsEmpty,
      tooMany: l10n.dictionaryContactsWindowsTooMany,
      unavailable: l10n.dictionaryContactsWindowsUnavailable,
      updating: l10n.dictionaryContactsWindowsUpdating,
      denied: l10n.dictionaryContactsWindowsDenied,
      restricted: l10n.dictionaryContactsWindowsDenied,
      unpackaged: l10n.dictionaryContactsWindowsUnpackaged,
    ),
    kMacContactsKind => _SystemTexts(
      read: l10n.dictionaryContactsMacRead,
      source: l10n.dictionaryContactsMacSource,
      changed: l10n.dictionaryContactsMacChanged,
      dropped: l10n.dictionaryContactsMacDropped,
      empty: l10n.dictionaryContactsMacEmpty,
      tooMany: l10n.dictionaryContactsMacTooMany,
      unavailable: l10n.dictionaryContactsMacUnavailable,
      updating: l10n.dictionaryContactsMacUpdating,
      denied: l10n.dictionaryContactsMacDenied,
      restricted: l10n.dictionaryContactsMacRestricted,
    ),
    // Every Outlook failure ends in the same way out: a CSV export from
    // Outlook through the file import.
    kOutlookContactsKind => _SystemTexts(
      read: l10n.dictionaryContactsOutlookRead,
      source: l10n.dictionaryContactsOutlookSource,
      dropped: l10n.dictionaryContactsOutlookDropped,
      empty: l10n.dictionaryContactsOutlookEmpty,
      tooMany: l10n.dictionaryContactsOutlookTooMany,
      unavailable: l10n.dictionaryContactsOutlookUnavailable,
      updating: l10n.dictionaryContactsOutlookUpdating,
      notInstalled: l10n.dictionaryContactsOutlookNotInstalled,
      notRunning: l10n.dictionaryContactsOutlookNotRunning,
      busy: l10n.dictionaryContactsOutlookBusy,
    ),
    kGnomeContactsKind => _SystemTexts(
      read: l10n.dictionaryContactsGnomeRead,
      source: l10n.dictionaryContactsGnomeSource,
      changed: l10n.dictionaryContactsGnomeChanged,
      dropped: l10n.dictionaryContactsGnomeDropped,
      empty: l10n.dictionaryContactsGnomeEmpty,
      tooMany: l10n.dictionaryContactsGnomeTooMany,
      unavailable: l10n.dictionaryContactsGnomeUnavailable,
      updating: l10n.dictionaryContactsGnomeUpdating,
      sandboxed: l10n.dictionaryContactsGnomeSandboxed,
    ),
    kKdeContactsKind => _SystemTexts(
      read: l10n.dictionaryContactsKdeRead,
      source: l10n.dictionaryContactsKdeSource,
      changed: l10n.dictionaryContactsKdeChanged,
      dropped: l10n.dictionaryContactsKdeDropped,
      empty: l10n.dictionaryContactsKdeEmpty,
      tooMany: l10n.dictionaryContactsKdeTooMany,
      unavailable: l10n.dictionaryContactsKdeUnavailable,
      updating: l10n.dictionaryContactsKdeUpdating,
      sandboxed: l10n.dictionaryContactsKdeSandboxed,
    ),
    _ => null,
  };

  String failure(ContactSourceFailure failure) => switch (failure) {
    ContactSourceFailure.denied => denied ?? unavailable,
    ContactSourceFailure.restricted => restricted ?? unavailable,
    ContactSourceFailure.unpackaged => unpackaged ?? unavailable,
    ContactSourceFailure.tooMany => tooMany,
    ContactSourceFailure.unavailable => unavailable,
    ContactSourceFailure.notInstalled => notInstalled ?? unavailable,
    ContactSourceFailure.notRunning => notRunning ?? unavailable,
    ContactSourceFailure.busy => busy ?? unavailable,
  };
}

/// One imported source: its name count, update and removal.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.index,
    required this.group,
    required this.name,
    required this.count,
    required this.busy,
    required this.onUpdate,
    required this.onRemove,
  });

  final int index;
  final ContactNameGroup group;

  /// What the user recognises the source by.
  final String name;
  final int count;
  final bool busy;

  /// `null` hides the update: a system group without access to its source.
  final VoidCallback? onUpdate;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'dictionary-contacts-group-$index',
      child: Padding(
        padding: const EdgeInsets.only(bottom: WpSpacing.sm),
        child: Wrap(
          spacing: WpSpacing.buttonGap,
          runSpacing: WpSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.dictionaryContactsGroup(name, count)),
            if (onUpdate != null)
              WpButton(
                testId: 'dictionary-contacts-group-update-$index',
                label: l10n.dictionaryContactsUpdate,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
                onPressed: busy ? null : onUpdate,
              ),
            WpButton(
              testId: 'dictionary-contacts-group-remove-$index',
              label: l10n.dictionaryContactsRemove,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.danger,
              size: WpButtonSize.dense,
              onPressed: busy ? null : () => onRemove(count),
            ),
          ],
        ),
      ),
    );
  }
}
