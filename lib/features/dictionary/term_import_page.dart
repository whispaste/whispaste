import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/term_import.dart';
import '../../services/dictionary/vocabulary_terms.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_page_header.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../replacements/replacements_page.dart';
import 'term_store.dart';

const _termTypes = XTypeGroup(
  label: 'CSV / Text / JSON',
  extensions: ['csv', 'txt', 'tsv', 'json'],
  uniformTypeIdentifiers: ['public.text', 'public.json'],
);

class TermTransferActions extends ConsumerStatefulWidget {
  const TermTransferActions({super.key});
  @override
  ConsumerState<TermTransferActions> createState() =>
      _TermTransferActionsState();
}

class _TermTransferActionsState extends ConsumerState<TermTransferActions> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final vocabulary =
        ref.watch(settingsProvider).value?.stt.customVocabulary ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: WpSpacing.buttonGap,
          children: [
            WpButton(
              testId: 'dictionary-terms-import',
              label: l10n.dictionaryTermImport,
              variant: WpButtonVariant.secondary,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await openTermImport(context);
                      if (mounted) setState(() => _busy = false);
                    },
            ),
            WpButton(
              testId: 'dictionary-terms-export',
              label: l10n.dictionaryCsvExport,
              variant: WpButtonVariant.secondary,
              onPressed: _busy || vocabularyTerms(vocabulary).isEmpty
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final message = await exportTerms(context, vocabulary);
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _message = message;
                        });
                      }
                    },
            ),
          ],
        ),
        if (_message != null)
          Semantics(
            liveRegion: true,
            identifier: 'dictionary-terms-export-result',
            child: Text(_message!),
          ),
      ],
    );
  }
}

Future<void> openTermImport(BuildContext context, {XFile? file}) =>
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => TermImportPage(file: file)));

/// Shared by dictionary settings and onboarding. All errors stay on this
/// page, including file chooser failures, so onboarding needs no notice slot.
class TermImportPage extends ConsumerStatefulWidget {
  const TermImportPage({super.key, this.file});
  final XFile? file;

  @override
  ConsumerState<TermImportPage> createState() => _TermImportPageState();
}

class _TermImportPageState extends ConsumerState<TermImportPage> {
  List<String?> _candidates = [];
  final Set<int> _excluded = {};
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.file != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _read(widget.file);
      });
    }
  }

  Future<void> _read([XFile? dropped]) async {
    if (_busy) return;
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      final file =
          dropped ?? await openFile(acceptedTypeGroups: const [_termTypes]);
      if (file == null) return;
      final bookmark = file is DropItem ? file.extraAppleBookmark : null;
      final scoped =
          bookmark != null &&
          bookmark.isNotEmpty &&
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
      final Uint8List bytes;
      try {
        if (await file.length() > termImportMaxBytes) {
          throw const FormatException('size');
        }
        bytes = await file.readAsBytes();
      } finally {
        if (scoped) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        }
      }
      final terms = decodeTermImport(bytes, filename: file.name);
      if (!mounted) return;
      setState(() {
        _candidates = terms;
        _excluded.clear();
        _message = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _candidates = [];
        _message = l10n.dictionaryTermImportError;
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(List<TermImportRow> rows) async {
    if (_busy) return;
    final l10n = L10n.of(context);
    final selected = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].status == TermImportStatus.fresh && !_excluded.contains(i))
          rows[i].term,
    ];
    setState(() => _busy = true);
    try {
      final replacements = await ref.read(replacementsProvider.future);
      final triggers = [for (final r in replacements) ...r.triggers];
      var added = 0;
      if (!mounted) return;
      await saveDictionaryVocabulary(
        ProviderScope.containerOf(context, listen: false),
        (previous) {
          final merged = mergeImportedTerms(
            previous,
            selected,
            triggers: triggers,
          );
          added =
              vocabularyTerms(merged).length - vocabularyTerms(previous).length;
          return merged;
        },
      );
      if (!mounted) return;
      setState(() {
        _message = l10n.dictionaryCsvImportResult(
          rows.length,
          added,
          rows.length - added,
        );
        _failed = false;
        _candidates = [];
      });
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = l10n.dictionarySuggestionFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider);
    final replacements = ref.watch(replacementsProvider);
    final ready =
        settings.hasValue &&
        !settings.hasError &&
        replacements.hasValue &&
        !replacements.hasError;
    final rows = planTermImport(
      _candidates,
      vocabulary: settings.value?.stt.customVocabulary ?? '',
      triggers: [
        for (final r in replacements.value ?? <Replacement>[]) ...r.triggers,
      ],
    );
    final count = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].status == TermImportStatus.fresh && !_excluded.contains(i))
          i,
    ].length;
    return Scaffold(
      body: Semantics(
        identifier: 'dictionary-term-import-page',
        child: DropTarget(
          onDragDone: (details) {
            if (_busy) return;
            if (details.files.length == 1) {
              _read(details.files.single);
            } else {
              setState(() {
                _candidates = [];
                _message = l10n.dictionaryTermImportError;
                _failed = true;
              });
            }
          },
          child: WpPageShell(
            scrollable: false,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WpPageHeader(title: l10n.dictionaryTermImport),
                const SizedBox(height: WpSpacing.sm),
                Text(l10n.dictionaryTermImportHint),
                const SizedBox(height: WpSpacing.sm),
                Wrap(
                  spacing: WpSpacing.buttonGap,
                  children: [
                    WpButton(
                      testId: 'dictionary-term-import-pick',
                      variant: WpButtonVariant.secondary,
                      label: l10n.dictionaryTermImportPick,
                      onPressed: _busy ? null : () => _read(),
                    ),
                    WpButton(
                      testId: 'dictionary-term-import-confirm',
                      variant: WpButtonVariant.primary,
                      label: l10n.dictionaryCsvPreviewAddCount(count),
                      onPressed: !_busy && ready && count > 0
                          ? () => _confirm(rows)
                          : null,
                    ),
                    WpButton(
                      testId: 'dictionary-term-import-close',
                      label: l10n.actionClose,
                      variant: WpButtonVariant.ghost,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (_message != null)
                  WpBanner(
                    message: _message!,
                    tone: _failed ? WpBannerTone.error : WpBannerTone.info,
                  ),
                if (settings.hasError || replacements.hasError)
                  WpBanner(
                    message: l10n.errorGeneric,
                    tone: WpBannerTone.error,
                  ),
              ],
            ),
            child: ListView.builder(
              key: const ValueKey('dictionary-term-import-preview'),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final status = switch (row.status) {
                  TermImportStatus.fresh => l10n.dictionaryTermImportNew,
                  TermImportStatus.existing =>
                    l10n.dictionaryTermImportExisting,
                  TermImportStatus.invalid => l10n.dictionaryTermImportInvalid,
                };
                return Semantics(
                  identifier: 'dictionary-term-import-row-$i',
                  child: Row(
                    children: [
                      if (row.status == TermImportStatus.fresh)
                        Semantics(
                          identifier: 'dictionary-term-import-select-$i',
                          child: WpRowCheckbox(
                            key: ValueKey('dictionary-term-import-select-$i'),
                            value: !_excluded.contains(i),
                            semanticsLabel: row.term,
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
                          child: Text('${row.term} — $status'),
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

/// Export writes only after a native save dialog has confirmed the destination.
Future<String?> exportTerms(BuildContext context, String vocabulary) async {
  final l10n = L10n.of(context);
  try {
    final terms = vocabularyTerms(vocabulary);
    final text = encodeTermsCsv(terms);
    if (terms.length > termImportMaxRows ||
        utf8.encode(text).length > termImportMaxBytes) {
      return l10n.dictionaryCsvExportTooMany(terms.length);
    }
    final location = await getSaveLocation(
      suggestedName: 'whispaste-terms.csv',
      acceptedTypeGroups: const [_termTypes],
    );
    if (location == null) return null;
    await XFile.fromData(
      utf8.encode(text),
      mimeType: 'text/csv',
    ).saveTo(location.path);
    return l10n.dictionaryCsvExportDone(terms.length);
  } on Object {
    return l10n.dictionaryCsvExportFailed;
  }
}
