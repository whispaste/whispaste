/// Compares an older version of a text with the current one, word by word
/// (#637). Shared by the version lists of recording transcripts and notes.
///
/// Only the sections that differ are shown. Added words are underlined and
/// removed words struck through, and every run also carries a spoken label
/// ("Added: ..."), so the difference never depends on colour. A section can be
/// taken over from the old version; the replaced text is kept by the caller as
/// a version of its own. The comparison runs in a background isolate, so a
/// text of 20,000 words does not freeze the window.
library;

import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/text/text_comparison.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'dialog.dart';
import 'wp_button.dart';
import 'wp_row_divider.dart';

final _log = AppLogger('VersionCompare');

/// Opens the comparison of [versionText] (older) with [currentText].
///
/// [apply] stores a new current text when a section is taken over. [idPrefix]
/// (`history`, `notes`) scopes the test ids. Resolves to `true` when at least
/// one section was taken over.
Future<bool> showWpVersionCompareDialog({
  required BuildContext context,
  required String idPrefix,
  required String versionText,
  required String currentText,
  required Future<void> Function(String newText) apply,
}) async {
  final l10n = L10n.of(context);
  final session = _CompareSession(currentText);
  await showWpDialog<bool>(
    context: context,
    title: l10n.versionCompare,
    size: WpDialogSize.wide,
    content: SizedBox(
      height: 460,
      child: _CompareBody(
        idPrefix: idPrefix,
        versionText: versionText,
        session: session,
        apply: apply,
      ),
    ),
    transition: WpMotion.normal,
    actions: [
      WpDialogAction(
        label: l10n.historyClose,
        testId: '$idPrefix-version-compare-close',
        role: WpDialogActionRole.primary,
        value: false,
      ),
    ],
  );
  return session.changed;
}

class _CompareSession {
  _CompareSession(this.current);

  String current;
  bool changed = false;
}

class _CompareBody extends StatefulWidget {
  const _CompareBody({
    required this.idPrefix,
    required this.versionText,
    required this.session,
    required this.apply,
  });

  final String idPrefix;
  final String versionText;
  final _CompareSession session;
  final Future<void> Function(String newText) apply;

  @override
  State<_CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends State<_CompareBody> {
  TextComparison? _result;
  bool _failed = false;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _compare();
  }

  Future<void> _compare() async {
    final older = widget.versionText;
    final current = widget.session.current;
    try {
      final r = await Isolate.run(() => compareTexts(older, current));
      if (!mounted) return;
      setState(() {
        _result = r;
        _failed = false;
      });
    } catch (e, st) {
      _log.warning('Could not compare versions', e, st);
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _takeOver(int index) async {
    final result = _result;
    if (result == null || _busy) return;
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.versionCompareTakeOver,
      message: l10n.versionCompareTakeOverMessage,
      confirmLabel: l10n.versionCompareTakeOver,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final next = result.takeOver(index);
      await widget.apply(next);
      widget.session.current = next;
      widget.session.changed = true;
      _status = l10n.versionCompareTakenOver;
      await _compare();
    } catch (e, st) {
      _log.warning('Could not take over a section', e, st);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (_failed) return Center(child: Text(l10n.errorGeneric));
    final result = _result;
    if (result == null) {
      return Semantics(
        label: l10n.versionCompareWorking,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final p = widget.idPrefix;
    if (result.identical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_status != null) _StatusLine(p, _status!),
          Expanded(
            child: Center(
              child: Text(
                l10n.versionCompareIdentical,
                key: ValueKey('$p-version-compare-identical'),
                style: TextStyle(color: WpColors.textMuted),
              ),
            ),
          ),
        ],
      );
    }
    final added = result.hunks.fold(0, (n, h) => n + h.addedWords);
    final removed = result.hunks.fold(0, (n, h) => n + h.removedWords);
    final unchanged = result.unchangedSections;
    final small = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_status != null) _StatusLine(p, _status!),
        Semantics(
          identifier: '$p-version-compare-summary',
          child: Text(
            l10n.versionCompareSummary(added, removed),
            style: TextStyle(
              fontSize: WpTypography.body,
              fontWeight: FontWeight.w600,
              color: WpColors.textPrimary,
            ),
          ),
        ),
        Text(l10n.versionCompareLegend, style: small),
        if (unchanged > 0)
          Text(l10n.versionCompareUnchanged(unchanged), style: small),
        const SizedBox(height: WpSpacing.xs),
        Expanded(
          child: Semantics(
            identifier: '$p-version-compare-list',
            child: ListView.separated(
              itemCount: result.hunks.length,
              separatorBuilder: (_, _) => const WpRowDivider(),
              itemBuilder: (context, i) => _HunkTile(
                idPrefix: p,
                index: i,
                hunk: result.hunks[i],
                onTakeOver: _busy ? null : () => _takeOver(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.prefix, this.text);

  final String prefix;
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    identifier: '$prefix-version-compare-status',
    child: Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Text(text, style: TextStyle(color: WpColors.success)),
    ),
  );
}

class _HunkTile extends StatelessWidget {
  const _HunkTile({
    required this.idPrefix,
    required this.index,
    required this.hunk,
    required this.onTakeOver,
  });

  final String idPrefix;
  final int index;
  final TextHunk hunk;
  final VoidCallback? onTakeOver;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = hunk.onlyInCurrent
        ? l10n.versionCompareSectionAdded
        : hunk.onlyInOld
        ? l10n.versionCompareSectionRemoved
        : l10n.versionCompareSectionChanged;
    final base = TextStyle(
      fontSize: WpTypography.body,
      height: 1.5,
      color: WpColors.textPrimary,
    );
    final spans = <InlineSpan>[];
    for (final s in hunk.spans) {
      final gap = spans.isEmpty ? '' : ' ';
      switch (s.kind) {
        case DiffKind.same:
          spans.add(TextSpan(text: '$gap${s.text}'));
        case DiffKind.added:
          spans.add(TextSpan(text: gap));
          spans.add(
            TextSpan(
              text: s.text,
              semanticsLabel: l10n.versionCompareAddedWords(s.text),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: WpColors.success,
                decoration: TextDecoration.underline,
                decorationColor: WpColors.success,
              ),
            ),
          );
        case DiffKind.removed:
          spans.add(TextSpan(text: gap));
          spans.add(
            TextSpan(
              text: s.text,
              semanticsLabel: l10n.versionCompareRemovedWords(s.text),
              style: TextStyle(
                color: WpColors.error,
                decoration: TextDecoration.lineThrough,
                decorationColor: WpColors.error,
              ),
            ),
          );
      }
    }
    final rowId = '$idPrefix-version-compare-hunk-$index';
    return Semantics(
      identifier: rowId,
      container: true,
      child: Padding(
        key: ValueKey(rowId),
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: WpTypography.caption,
                fontWeight: FontWeight.w600,
                color: WpColors.textMuted,
              ),
            ),
            if (hunk.coarse)
              Text(
                l10n.versionCompareCoarse,
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textMuted,
                ),
              ),
            const SizedBox(height: WpSpacing.xxs),
            SelectableText.rich(TextSpan(style: base, children: spans)),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WpButton(
                testId: '$idPrefix-version-compare-takeover-$index',
                label: l10n.versionCompareTakeOver,
                variant: WpButtonVariant.ghost,
                icon: LucideIcons.undo2,
                onPressed: onTakeOver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
