/// The links row above an editor (#660): "Back to …" after a jump over a
/// link, the entries this text links to ("Links to") and the entries that
/// link here ("Linked from"). Each name opens its entry; every one is a
/// focusable link, so the row works by keyboard and screen reader alike.
///
/// Draws nothing while there is nothing to show, so an entry without links
/// keeps its editor exactly as before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/content_metadata.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_text_link.dart';
import 'data/providers.dart';
import 'entry_link_picker.dart' show entryLinkKindLabel, entryLinkTitle;

class EntryLinksSection extends ConsumerWidget {
  const EntryLinksSection({
    super.key,
    required this.entry,
    required this.testId,
  });

  /// The text on screen: a recording's raw or Smart Mode text, a note, a
  /// snippet. Its links are read from the saved text of that version.
  final ContentKey entry;

  /// Prefix of the row's ids (`<testId>-links`, `-links-back`,
  /// `-links-to-<kind>-<id>`, `-links-from-<kind>-<id>`).
  final String testId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final self = entryRefOf(entry);
    final backRef = entryLinkBackTarget(
      ref.watch(entryLinkTrailProvider),
      self,
    );
    final back = backRef == null
        ? null
        : ref.watch(linkedEntryProvider(backRef)).value;
    final outgoing =
        ref.watch(entryOutgoingLinksProvider(entry)).value ?? const [];
    final incoming = ref.watch(entryBacklinksProvider(self)).value ?? const [];
    if (back == null && outgoing.isEmpty && incoming.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[
      if (back != null)
        WpTextLink(
          testID: '$testId-links-back',
          label: l10n.entryLinkBack(entryLinkTitle(l10n, back)),
          kind: WpLinkKind.page,
          onPressed: () => goBackOverEntryLink(ref.read, self),
        ),
      if (outgoing.isNotEmpty)
        _LinkRow(
          testId: '$testId-links-to',
          label: l10n.entryLinksTo,
          children: [
            for (final link in outgoing)
              if (link.entry case final target?)
                WpTextLink(
                  testID:
                      '$testId-links-to-${link.ref.kind.prefix}-'
                      '${link.ref.id}',
                  label: entryLinkTitle(l10n, target),
                  semanticsLabel:
                      '${entryLinkKindLabel(l10n, link.ref.kind)}: '
                      '${entryLinkTitle(l10n, target)}',
                  kind: WpLinkKind.page,
                  onPressed: () => followEntryLink(ref.read, self, link.ref),
                )
              else
                Semantics(
                  identifier:
                      '$testId-links-missing-${link.ref.kind.prefix}-'
                      '${link.ref.id}',
                  child: Text(
                    l10n.entryLinkMissing,
                    style: TextStyle(
                      color: WpColors.textMuted,
                      fontSize: WpTypography.small,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
          ],
        ),
      if (incoming.isNotEmpty)
        _LinkRow(
          testId: '$testId-links-from',
          label: l10n.entryLinkedFrom,
          children: [
            for (final source in incoming)
              WpTextLink(
                testID:
                    '$testId-links-from-${source.ref.kind.prefix}-'
                    '${source.ref.id}',
                label: entryLinkTitle(l10n, source),
                semanticsLabel:
                    '${entryLinkKindLabel(l10n, source.ref.kind)}: '
                    '${entryLinkTitle(l10n, source)}',
                kind: WpLinkKind.page,
                onPressed: () => followEntryLink(ref.read, self, source.ref),
              ),
          ],
        ),
    ];

    return Semantics(
      container: true,
      identifier: '$testId-links',
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          WpSpacing.xl,
          0,
          WpSpacing.xl,
          WpSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: WpSpacing.xxs),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// "Links to: A  B  C", wrapping onto further lines when narrow.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.testId,
    required this.label,
    required this.children,
  });

  final String testId;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      identifier: testId,
      label: label,
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.small,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
