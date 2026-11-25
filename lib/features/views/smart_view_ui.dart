/// Shared UI of saved views (#658) for the Notizen and Aufnahmen pages: the
/// "Ansichten" group of the filter popover, the mark of the shown view, its
/// edit button, and the dialog that creates, edits, renames and deletes a
/// view. One look on both pages; only the [SmartViewScope] differs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/views/smart_view.dart';
import '../../core/views/smart_view_providers.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_collection_page.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_field.dart';

/// Visible name of [view]: built-in views are named by the app language,
/// the user's own by what the user typed.
String smartViewLabel(L10n l10n, SmartView view) {
  if (!view.builtIn) return view.name;
  return switch (view.id) {
    BuiltInSmartViews.recent => l10n.smartViewRecent,
    // The app calls pinned items "Favoriten" everywhere (star, filter), so
    // the view does too.
    BuiltInSmartViews.pinned => l10n.historyPinned,
    BuiltInSmartViews.untagged => l10n.smartViewUntagged,
    BuiltInSmartViews.quickNotes => l10n.smartViewQuickNotes,
    BuiltInSmartViews.checklist => l10n.smartViewChecklist,
    _ => view.name,
  };
}

IconData _viewIcon(SmartView view) => switch (view.id) {
  BuiltInSmartViews.recent => LucideIcons.clock,
  BuiltInSmartViews.pinned => LucideIcons.star,
  BuiltInSmartViews.untagged => LucideIcons.circleDashed,
  BuiltInSmartViews.quickNotes => LucideIcons.zap,
  BuiltInSmartViews.checklist => LucideIcons.listChecks,
  _ => LucideIcons.layers,
};

/// The "Ansichten" group of the filter popover on [screenId]: one chip per
/// view (a second tap goes back to the plain list) and "Neue Ansicht".
/// [loadTags] lists the tags the dialog offers as rules.
WpFilterSection smartViewFilterSection(
  BuildContext context,
  WidgetRef ref, {
  required SmartViewScope scope,
  required String screenId,
  required Future<List<Tag>> Function() loadTags,
  List<NoteFolder> folders = const [],
}) {
  final l10n = L10n.of(context);
  final views = ref.watch(allSmartViewsProvider(scope));
  final activeId = ref.watch(shownSmartViewProvider(scope))?.id;
  return WpFilterSection(
    id: 'views',
    label: l10n.smartViewGroup,
    children: [
      for (final view in views)
        WpFilterChip(
          testId: '$screenId-view-${view.id}',
          label: smartViewLabel(l10n, view),
          icon: _viewIcon(view),
          isActive: view.id == activeId,
          onTap: () =>
              ref.read(activeSmartViewProvider(scope).notifier).toggle(view.id),
        ),
      WpFilterChip(
        testId: '$screenId-view-new',
        label: l10n.smartViewNew,
        icon: LucideIcons.plus,
        isActive: false,
        onTap: () => openSmartViewDialog(
          context,
          ref,
          scope: scope,
          screenId: screenId,
          loadTags: loadTags,
          folders: folders,
        ),
      ),
    ],
  );
}

/// The mark of the shown view next to the search; removing it leaves the
/// view. Null while no view is shown.
WpActiveFilter? smartViewActiveFilter(
  BuildContext context,
  WidgetRef ref, {
  required SmartViewScope scope,
}) {
  final view = ref.watch(shownSmartViewProvider(scope));
  if (view == null) return null;
  return WpActiveFilter(
    id: 'view-${view.id}',
    label: smartViewLabel(L10n.of(context), view),
    onRemove: ref.read(activeSmartViewProvider(scope).notifier).clear,
  );
}

/// Status-row controls while a view is shown: the hint that nothing can be
/// created here, and for the user's own view the button that edits, renames
/// or deletes it. Empty while no view is shown.
List<Widget> smartViewStatus(
  BuildContext context,
  WidgetRef ref, {
  required SmartViewScope scope,
  required String screenId,
  required Future<List<Tag>> Function() loadTags,
  List<NoteFolder> folders = const [],
}) {
  final view = ref.watch(shownSmartViewProvider(scope));
  if (view == null) return const [];
  final l10n = L10n.of(context);
  return [
    Text(
      l10n.smartViewCreateHint,
      key: ValueKey('$screenId-view-create-hint'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: WpTypography.small, color: WpColors.textMuted),
    ),
    if (!view.builtIn)
      WpIconButton(
        key: ValueKey('$screenId-view-edit'),
        testId: '$screenId-view-edit',
        icon: LucideIcons.pencil,
        tooltip: l10n.smartViewEditTitle,
        onPressed: () => openSmartViewDialog(
          context,
          ref,
          scope: scope,
          screenId: screenId,
          loadTags: loadTags,
          folders: folders,
          existing: view,
        ),
      ),
  ];
}

/// Opens the view dialog. Without [existing] it creates a view and shows it
/// right away; with it, it saves the changes or deletes the view. Neither
/// touches a note or a recording.
Future<void> openSmartViewDialog(
  BuildContext context,
  WidgetRef ref, {
  required SmartViewScope scope,
  required String screenId,
  required Future<List<Tag>> Function() loadTags,
  List<NoteFolder> folders = const [],
  SmartView? existing,
}) async {
  final List<Tag> tags;
  try {
    tags = await loadTags();
  } on Object {
    return;
  }
  if (!context.mounted) return;
  final result = await showWpFormDialog<_SmartViewDialogResult>(
    context: context,
    builder: (context, animation) => _SmartViewDialog(
      animation: animation,
      scope: scope,
      screenId: screenId,
      tags: tags,
      folders: folders,
      existing: existing,
    ),
  );
  if (result == null) return;
  final notifier = ref.read(smartViewsProvider(scope).notifier);
  if (existing == null) {
    final view = await notifier.add(
      name: result.name,
      match: result.match,
      rules: result.rules,
    );
    ref.read(activeSmartViewProvider(scope).notifier).show(view.id);
  } else if (result.delete) {
    await notifier.delete(existing.id);
  } else {
    await notifier.edit(
      existing.id,
      name: result.name,
      match: result.match,
      rules: result.rules,
    );
  }
}

class _SmartViewDialogResult {
  const _SmartViewDialogResult({
    required this.name,
    required this.match,
    required this.rules,
  }) : delete = false;

  const _SmartViewDialogResult.deleted()
    : name = '',
      match = SmartViewMatch.all,
      rules = const [],
      delete = true;

  final String name;
  final SmartViewMatch match;
  final List<SmartRule> rules;
  final bool delete;
}

class _SmartViewDialog extends StatefulWidget {
  const _SmartViewDialog({
    required this.animation,
    required this.scope,
    required this.screenId,
    required this.tags,
    required this.folders,
    required this.existing,
  });

  final Animation<double> animation;
  final SmartViewScope scope;
  final String screenId;
  final List<Tag> tags;

  /// The note folders the view may name as rules (#659); empty on the
  /// Aufnahmen page and while no folder exists.
  final List<NoteFolder> folders;
  final SmartView? existing;

  @override
  State<_SmartViewDialog> createState() => _SmartViewDialogState();
}

class _SmartViewDialogState extends State<_SmartViewDialog> {
  late final TextEditingController _name;
  late SmartViewMatch _match;

  /// Tag rules by tag id, in the order the user picked them.
  final Map<String, TagRule> _tags = {};

  /// Folder rules by folder id, in the order the user picked them (#659).
  final Map<String, FolderRule> _folders = {};
  bool _untagged = false;
  SmartViewPeriod? _period;
  final Set<SmartViewSource> _sources = {};
  bool _checklist = false;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    final view = widget.existing;
    _name = TextEditingController(text: view?.name ?? '');
    _match = view?.match ?? SmartViewMatch.all;
    for (final rule in view?.rules ?? const <SmartRule>[]) {
      switch (rule) {
        case TagRule():
          _tags[rule.tagId] = rule;
        case UntaggedRule():
          _untagged = true;
        case PeriodRule():
          _period = rule.period;
        case SourceRule():
          _sources.add(rule.source);
        case ChecklistRule():
          _checklist = true;
        case PinnedRule():
          _pinned = true;
        case FolderRule():
          _folders[rule.folderId] = rule;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<SmartRule> get _rules => [
    ..._tags.values,
    ..._folders.values,
    if (_untagged) const UntaggedRule(),
    if (_period case final period?) PeriodRule(period),
    for (final s in sourcesFor(widget.scope))
      if (_sources.contains(s)) SourceRule(s),
    if (_checklist) const ChecklistRule(),
    if (_pinned) const PinnedRule(),
  ];

  bool get _valid => _name.text.trim().isNotEmpty && _rules.isNotEmpty;

  void _save() {
    if (!_valid) return;
    Navigator.of(context).pop(
      _SmartViewDialogResult(
        name: _name.text.trim(),
        match: _match,
        rules: _rules,
      ),
    );
  }

  Future<void> _delete() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.smartViewDeleteTitle(widget.existing?.name ?? ''),
      message: l10n.smartViewDeleteMessage,
      confirmLabel: l10n.actionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(const _SmartViewDialogResult.deleted());
  }

  void _toggleTag(Tag tag) => setState(() {
    if (_tags.remove(tag.id) == null) {
      _tags[tag.id] = TagRule(tagId: tag.id, tagName: tag.name);
    }
  });

  void _toggleFolder(String folderId, String folderName) => setState(() {
    if (_folders.remove(folderId) == null) {
      _folders[folderId] = FolderRule(
        folderId: folderId,
        folderName: folderName,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final id = '${widget.screenId}-view';
    // A subfolder is named with its parent, so two "Ideen" stay apart.
    // Folders the view names but that no longer exist stay listed, so the
    // user can still take them out.
    final folderById = {for (final f in widget.folders) f.id: f};
    final folderOptions = <({String id, String name})>[
      for (final f in widget.folders)
        (
          id: f.id,
          name: switch (folderById[f.parentId]) {
            final parent? => '${parent.name} / ${f.name}',
            null => f.name,
          },
        ),
      for (final rule in _folders.values)
        if (!folderById.containsKey(rule.folderId))
          (id: rule.folderId, name: rule.folderName),
    ];
    // Tags the view names but that no longer exist stay listed, so the user
    // can still take them out.
    final tagOptions = <({String id, String name})>[
      for (final t in widget.tags) (id: t.id, name: t.name),
      for (final rule in _tags.values)
        if (!widget.tags.any((t) => t.id == rule.tagId))
          (id: rule.tagId, name: rule.tagName),
    ];

    return WpFormDialogShell(
      animation: widget.animation,
      title: widget.existing == null
          ? l10n.smartViewNew
          : l10n.smartViewEditTitle,
      subtitle: l10n.smartViewSubtitle,
      fields: [
        _GroupLabel(l10n.smartViewName),
        WpTextField(
          testId: '$id-name',
          key: ValueKey('$id-name'),
          controller: _name,
          variant: WpTextFieldVariant.form,
          hintText: l10n.smartViewNameHint,
          semanticsLabel: l10n.smartViewName,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
        _GroupLabel(l10n.smartViewMatchLabel),
        _Chips([
          WpFilterChip(
            testId: '$id-match-all',
            label: l10n.smartViewMatchAll,
            isActive: _match == SmartViewMatch.all,
            onTap: () => setState(() => _match = SmartViewMatch.all),
          ),
          WpFilterChip(
            testId: '$id-match-any',
            label: l10n.smartViewMatchAny,
            isActive: _match == SmartViewMatch.any,
            onTap: () => setState(() => _match = SmartViewMatch.any),
          ),
        ]),
        _GroupLabel(l10n.smartViewRuleTags),
        _Chips([
          for (final tag in tagOptions)
            WpFilterChip(
              testId: '$id-tag-${tag.id}',
              label: tag.name,
              icon: LucideIcons.tag,
              isActive: _tags.containsKey(tag.id),
              onTap: () => _toggleTag(
                Tag(id: tag.id, name: tag.name, createdAt: DateTime(0)),
              ),
            ),
          WpFilterChip(
            testId: '$id-untagged',
            label: l10n.smartViewUntagged,
            icon: LucideIcons.circleDashed,
            isActive: _untagged,
            onTap: () => setState(() => _untagged = !_untagged),
          ),
        ]),
        // Flat by default (ADR 0034): the group only shows once a folder
        // exists or the view already names one.
        if (folderOptions.isNotEmpty) ...[
          _GroupLabel(l10n.smartViewRuleFolder),
          _Chips([
            for (final folder in folderOptions)
              WpFilterChip(
                testId: '$id-folder-${folder.id}',
                label: folder.name,
                icon: LucideIcons.folder,
                isActive: _folders.containsKey(folder.id),
                onTap: () => _toggleFolder(folder.id, folder.name),
              ),
          ]),
        ],
        _GroupLabel(l10n.smartViewRulePeriod),
        _Chips([
          for (final period in SmartViewPeriod.values)
            WpFilterChip(
              testId: '$id-period-${period.name}',
              label: switch (period) {
                SmartViewPeriod.today => l10n.smartViewPeriodToday,
                SmartViewPeriod.week => l10n.smartViewPeriodWeek,
                SmartViewPeriod.month => l10n.smartViewPeriodMonth,
              },
              icon: LucideIcons.calendar,
              isActive: _period == period,
              // A second tap takes the period out again.
              onTap: () =>
                  setState(() => _period = _period == period ? null : period),
            ),
        ]),
        _GroupLabel(l10n.smartViewRuleSource),
        _Chips([
          for (final source in sourcesFor(widget.scope))
            WpFilterChip(
              testId: '$id-source-${source.name}',
              label: switch (source) {
                SmartViewSource.dictation => l10n.smartViewSourceDictation,
                SmartViewSource.audioImport => l10n.smartViewSourceImport,
                SmartViewSource.quickNote => l10n.smartViewSourceQuickNote,
                SmartViewSource.fromRecording =>
                  l10n.smartViewSourceFromRecording,
              },
              icon: switch (source) {
                SmartViewSource.dictation => LucideIcons.mic,
                SmartViewSource.audioImport => LucideIcons.fileAudio,
                SmartViewSource.quickNote => LucideIcons.zap,
                SmartViewSource.fromRecording => LucideIcons.fileInput,
              },
              isActive: _sources.contains(source),
              onTap: () => setState(() {
                if (!_sources.remove(source)) _sources.add(source);
              }),
            ),
        ]),
        _GroupLabel(l10n.smartViewRuleMore),
        _Chips([
          WpFilterChip(
            testId: '$id-checklist',
            label: l10n.smartViewChecklist,
            icon: LucideIcons.listChecks,
            isActive: _checklist,
            onTap: () => setState(() => _checklist = !_checklist),
          ),
          WpFilterChip(
            testId: '$id-pinned',
            label: l10n.historyPinned,
            icon: LucideIcons.star,
            isActive: _pinned,
            onTap: () => setState(() => _pinned = !_pinned),
          ),
        ]),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: '$id-cancel',
          role: WpDialogActionRole.cancel,
        ),
        if (widget.existing != null)
          WpDialogAction<Object?>(
            label: l10n.smartViewDelete,
            testId: '$id-delete',
            role: WpDialogActionRole.alternative,
            onPressed: () => _delete(),
          ),
        WpDialogAction<Object?>(
          label: l10n.actionSave,
          testId: '$id-save',
          role: WpDialogActionRole.primary,
          enabled: _valid,
          onPressed: _valid ? _save : null,
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WpSpacing.md, bottom: WpSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: WpColors.textMuted),
      ),
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: WpSpacing.xs, runSpacing: WpSpacing.xs, children: children);
}
