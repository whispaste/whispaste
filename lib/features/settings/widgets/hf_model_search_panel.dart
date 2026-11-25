/// The Hugging-Face-Suche inside the "+" dialog of the model library
/// (#2047): consent card first, then the search field with the sort button,
/// one filter row (languages for speech, size), an endless result list and
/// the detail of one repo with its runnable files (#2193).
///
/// Picking a file hands a [UserModelDraft] to the dialog ([onDraft]); terms,
/// hosts, free space and the install itself stay the existing own-model path
/// (#1789). Nothing is sent to huggingface.co before the user agreed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/locale_native_name.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/text/byte_size.dart';
import '../../../core/text/name_order.dart' show compareDisplayNames;
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/speech_recommendation.dart'
    show dictationLanguagesProvider, ramMBProvider;
import '../../../services/user_models/hf_model_search.dart';
import '../../../services/user_models/hf_repo_resolver.dart';
import '../../../services/user_models/user_model.dart';
import '../../../services/user_models/user_model_address.dart';
import '../../../services/user_models/user_model_installer.dart';
import '../../../services/user_models/user_models_provider.dart';
import '../../../widgets/external_link.dart';
import '../../../widgets/wp_accent_badge.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_dropdown.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_list_tile_surface.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_sort_menu_button.dart';
import '../../../widgets/wp_text_link.dart';
import 'wp_language_dialog.dart';

/// Builds the search client; replaced in tests.
final hfModelSearchFactoryProvider =
    Provider<HfModelSearch Function(bool Function() hasConsent)>(
      (_) =>
          (hasConsent) => HfModelSearch(hasConsent: hasConsent),
    );

/// Reads one repo for the detail; replaced in tests.
final hfRepoResolveProvider = Provider<HfRepoResolve>((_) => resolveHfRepo);

class HfModelSearchPanel extends ConsumerStatefulWidget {
  const HfModelSearchPanel({
    super.key,
    required this.purpose,
    required this.onDraft,
  });

  final UserModelPurpose purpose;

  /// The picked file as a draft, or null when the pick was undone.
  final ValueChanged<UserModelDraft?> onDraft;

  @override
  ConsumerState<HfModelSearchPanel> createState() => _HfModelSearchPanelState();
}

class _HfModelSearchPanelState extends ConsumerState<HfModelSearchPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late HfModelSearch _search;
  late HfSearchQuery _query;

  /// The user's dictation languages, the "my languages" choice.
  late List<String> _myLanguages;
  Timer? _debounce;

  List<HfModelHit> _hits = const [];
  HfSearchCursor? _next;
  bool _loading = false;
  HfSearchException? _error;
  int _generation = 0;

  /// Loads in a row that brought nothing new. After [_maxEmptyLoads] the list
  /// stops reading on by itself and offers "Weiter suchen", so a narrow filter
  /// on a large stream does not run into the Hub's request limit.
  int _emptyLoads = 0;
  static const _maxEmptyLoads = 3;
  bool get _autoMore => _emptyLoads < _maxEmptyLoads;

  HfModelHit? _open;
  List<HfInstallOption>? _options;
  HfRepoSnapshot? _snapshot;
  HfInstallOption? _picked;
  bool _resolving = false;
  HfResolveError? _resolveError;

  @override
  void initState() {
    super.initState();
    _search = ref.read(hfModelSearchFactoryProvider)(
      () => ref.read(userModelsProvider).hfSearchConsent,
    );
    final ramMB = ref.read(ramMBProvider);
    _myLanguages = hfInitialLanguages(
      widget.purpose,
      ref.read(dictationLanguagesProvider),
    );
    _query = HfSearchQuery(
      purpose: widget.purpose,
      languages: _myLanguages,
      size: HfSizeFilter.initial(ramMB: ramMB),
      ramMB: ramMB,
    );
    _scroll.addListener(_onScroll);
    if (ref.read(userModelsProvider).hfSearchConsent) _restart();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _scroll.dispose();
    _search.close();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 200) unawaited(_loadMore());
  }

  void _setQuery(HfSearchQuery query) {
    setState(() => _query = query);
    _restart();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && value.trim() != _query.text.trim()) {
        _setQuery(_query.copyWith(text: value));
      }
    });
  }

  /// Starts the current query from the top. Answers of earlier queries that
  /// arrive later are dropped ([_generation]).
  void _restart() {
    _generation++;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _hits = const [];
      _next = null;
      _error = null;
      _loading = false;
      _emptyLoads = 0;
    });
    unawaited(_load(first: true));
  }

  Future<void> _loadMore() async {
    if (_loading || _next == null || _error != null || !_autoMore) return;
    await _load(first: false);
  }

  /// Reads on after the list stopped by itself ([_autoMore]).
  void _searchOn() {
    setState(() => _emptyLoads = 0);
    unawaited(_loadMore());
  }

  /// Retries the load that failed, keeping the hits already shown.
  void _retryMore() {
    setState(() => _error = null);
    unawaited(_load(first: _hits.isEmpty && _next == null));
  }

  Future<void> _load({required bool first}) async {
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await _search.search(_query, next: first ? null : _next);
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = [..._hits, ...page.hits];
        _next = page.next;
        _loading = false;
        _emptyLoads = page.hits.isEmpty ? _emptyLoads + 1 : 0;
      });
    } on HfSearchException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _agree() {
    ref.read(userModelsProvider.notifier).setHfSearchConsent(true);
    _restart();
  }

  /// Whether a filter narrows the list (offered as "Filter lockern" when
  /// nothing is found).
  bool get _filtered =>
      _query.languages.isNotEmpty || _query.size != HfSizeFilter.any;

  void _relaxFilters() =>
      _setQuery(_query.copyWith(languages: const [], size: HfSizeFilter.any));

  Future<void> _openHit(HfModelHit hit) async {
    setState(() {
      _open = hit;
      _options = null;
      _snapshot = null;
      _picked = null;
      _resolveError = null;
      _resolving = !hit.gated;
    });
    widget.onDraft(null);
    if (hit.gated) return;
    final address = HuggingFaceAddress(owner: hit.author, repo: hit.name);
    try {
      // The size lookup of the list may already have read the repo.
      final snapshot =
          await _search.snapshot(hit) ??
          await ref.read(hfRepoResolveProvider)(address);
      if (!mounted || _open != hit) return;
      final options = installOptionsFor(
        snapshot.files,
        repoId: snapshot.repoId,
        kinds: hit.kinds,
        ramMB: ref.read(ramMBProvider),
      );
      setState(() {
        _snapshot = snapshot;
        _options = options;
        _resolving = false;
      });
      _pick(preferredOption(options));
    } on HfResolveException catch (e) {
      if (!mounted || _open != hit) return;
      setState(() {
        _resolving = false;
        _resolveError = e.error;
      });
    }
  }

  void _pick(HfInstallOption? option) {
    final snapshot = _snapshot;
    setState(() => _picked = option);
    widget.onDraft(
      option == null || snapshot == null
          ? null
          : draftFromHfSnapshot(snapshot, option.candidate),
    );
  }

  void _close() {
    setState(() => _open = null);
    widget.onDraft(null);
  }

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(
      userModelsProvider.select((s) => s.hfSearchConsent),
    );
    if (!consent) return _ConsentCard(onAgree: _agree);
    final open = _open;
    if (open != null) return _detail(context, open);
    return _list(context);
  }

  // -------------------------------------------------------------------------
  // List
  // -------------------------------------------------------------------------

  String _languageName(BuildContext context, String code) =>
      LocaleNames.of(context)?.nameOf(code) ?? whisperLanguages[code] ?? code;

  String _languageList(BuildContext context, List<String> codes) =>
      codes.map((c) => _languageName(context, c)).join(', ');

  Future<void> _pickLanguages() async {
    final l10n = L10n.of(context);
    final options = [
      for (final code in whisperLanguages.keys)
        WpLanguageOption(
          code: code,
          name: _languageName(context, code),
          endonym: localeNativeName(Locale(code)),
        ),
    ]..sort((a, b) => compareDisplayNames(a.name, b.name));
    final selection = await showWpLanguageDialog(
      context: context,
      multiple: true,
      title: l10n.modelLibraryHfLanguagesTitle,
      subtitle: l10n.modelLibraryHfLanguagesHint,
      emptySelectionLabel: l10n.modelLibraryHfLanguageAll,
      options: options,
      initial: WpLanguageSelection(autoDetect: false, codes: _query.languages),
    );
    if (selection == null || !mounted) return;
    _setQuery(_query.copyWith(languages: selection.codes));
  }

  Widget _languageFilter(BuildContext context) {
    final l10n = L10n.of(context);
    final current = _query.languages;
    final choice = current.isEmpty
        ? _LanguageChoice.all
        : _sameLanguages(current, _myLanguages)
        ? _LanguageChoice.mine
        : _LanguageChoice.custom;
    return Semantics(
      container: true,
      label: l10n.modelLibraryHfFilterLanguage,
      child: WpDropdown<_LanguageChoice>(
        testId: 'model-library-hf-language',
        expanded: true,
        value: choice,
        items: [
          if (_myLanguages.isNotEmpty)
            WpDropdownItem(
              value: _LanguageChoice.mine,
              itemKey: const ValueKey('model-library-hf-language-mine'),
              label: l10n.modelLibraryHfLanguageMine(
                _languageList(context, _myLanguages),
              ),
            ),
          WpDropdownItem(
            value: _LanguageChoice.all,
            itemKey: const ValueKey('model-library-hf-language-all'),
            label: l10n.modelLibraryHfLanguageAll,
          ),
          if (choice == _LanguageChoice.custom)
            WpDropdownItem(
              value: _LanguageChoice.custom,
              itemKey: const ValueKey('model-library-hf-language-custom'),
              label: _languageList(context, current),
            ),
          WpDropdownItem(
            value: _LanguageChoice.pick,
            itemKey: const ValueKey('model-library-hf-language-pick'),
            label: l10n.modelLibraryHfLanguagePick,
          ),
        ],
        onChanged: (v) {
          switch (v) {
            case _LanguageChoice.mine:
              _setQuery(_query.copyWith(languages: _myLanguages));
            case _LanguageChoice.all:
              _setQuery(_query.copyWith(languages: const []));
            case _LanguageChoice.pick:
              unawaited(_pickLanguages());
            case _LanguageChoice.custom || null:
              break;
          }
        },
      ),
    );
  }

  Widget _sizeFilter(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      container: true,
      label: l10n.modelLibraryHfFilterSize,
      child: WpDropdown<HfSizeFilter>(
        testId: 'model-library-hf-size',
        expanded: true,
        value: _query.size,
        items: [
          for (final f in HfSizeFilter.choices(ramMB: _query.ramMB))
            WpDropdownItem(
              value: f,
              itemKey: ValueKey('model-library-hf-size-${f.name}'),
              label: _sizeLabel(l10n, f),
            ),
        ],
        onChanged: (f) {
          if (f != null && f != _query.size) {
            _setQuery(_query.copyWith(size: f));
          }
        },
      ),
    );
  }

  Widget _list(BuildContext context) {
    final l10n = L10n.of(context);
    final sortLabel = _sortLabel(l10n, _query.sort);
    final speech = widget.purpose == UserModelPurpose.speech;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: WpSearchField(
                testId: 'model-library-hf-search',
                controller: _text,
                variant: WpSearchFieldVariant.outlined,
                hintText: speech
                    ? l10n.modelLibraryHfSearchHint
                    : l10n.modelLibraryHfSearchHintText,
                semanticsLabel: l10n.modelLibraryHfSearchLabel,
                autofocus: true,
                onChanged: _onTextChanged,
                onSubmitted: (v) {
                  _debounce?.cancel();
                  _setQuery(_query.copyWith(text: v));
                },
                onClear: () {
                  _debounce?.cancel();
                  _setQuery(_query.copyWith(text: ''));
                },
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            WpSortMenuButton<HfSearchSort>(
              testId: 'model-library-hf-sort',
              tooltip: l10n.modelLibraryHfSortTooltip(sortLabel),
              current: _query.sort,
              options: [
                for (final s in HfSearchSort.values)
                  WpSortOption(
                    value: s,
                    id: s.name,
                    label: _sortLabel(l10n, s),
                    icon: switch (s) {
                      HfSearchSort.downloads => LucideIcons.download,
                      HfSearchSort.likes => LucideIcons.heart,
                      HfSearchSort.lastModified => LucideIcons.clock,
                    },
                  ),
              ],
              onChanged: (s) {
                if (s != _query.sort) _setQuery(_query.copyWith(sort: s));
              },
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Row(
          children: [
            if (speech) ...[
              Expanded(child: _languageFilter(context)),
              const SizedBox(width: WpSpacing.xs),
            ],
            Expanded(child: _sizeFilter(context)),
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.modelLibraryHfListNote,
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        SizedBox(height: 300, child: _results(context)),
      ],
    );
  }

  Widget _retryButton(L10n l10n, VoidCallback onPressed) => WpButton(
    testId: 'model-library-hf-retry',
    label: l10n.modelLibraryHfRetry,
    variant: WpButtonVariant.secondary,
    onPressed: onPressed,
  );

  Widget _searchOnButton(L10n l10n) => WpButton(
    testId: 'model-library-hf-search-on',
    label: l10n.modelLibraryHfSearchOn,
    variant: WpButtonVariant.secondary,
    onPressed: _searchOn,
  );

  Widget _results(BuildContext context) {
    final l10n = L10n.of(context);
    final error = _error;
    if (_hits.isEmpty && error != null) {
      return _Message(
        testId: 'model-library-hf-error',
        text: _errorText(l10n, error),
        action: error.error == HfSearchError.noConsent
            ? null
            : _retryButton(l10n, _retryMore),
      );
    }
    if (_hits.isEmpty && (_loading || (_next != null && _autoMore))) {
      // An empty first load with more to read goes on by itself.
      if (!_loading) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_loadMore()),
        );
      }
      return Center(
        child: Semantics(
          label: l10n.modelLibraryHfLoading,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_hits.isEmpty) {
      return _Message(
        testId: 'model-library-hf-empty',
        text: _filtered
            ? l10n.modelLibraryHfEmptyFiltered
            : l10n.modelLibraryHfEmpty,
        action: Wrap(
          spacing: WpSpacing.buttonGap,
          runSpacing: WpSpacing.xs,
          children: [
            if (_filtered)
              WpButton(
                testId: 'model-library-hf-relax',
                label: l10n.modelLibraryHfRelaxFilters,
                variant: WpButtonVariant.secondary,
                onPressed: _relaxFilters,
              ),
            if (_next != null) _searchOnButton(l10n),
          ],
        ),
      );
    }
    final more = _next != null || _loading || error != null;
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scroll,
        itemCount: _hits.length + (more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i < _hits.length) {
            final hit = _hits[i];
            return _HitRow(
              key: ValueKey('model-library-hf-hit-${hit.repoId}'),
              hit: hit,
              ramMB: _query.ramMB,
              languageNames: _hitLanguages(context, hit),
              onOpen: () => unawaited(_openHit(hit)),
            );
          }
          if (error != null) {
            return Padding(
              padding: const EdgeInsets.all(WpSpacing.xs),
              child: _Message(
                testId: 'model-library-hf-more-error',
                text: _errorText(l10n, error),
                action: _retryButton(l10n, _retryMore),
              ),
            );
          }
          if (!_loading && !_autoMore) {
            return Padding(
              padding: const EdgeInsets.all(WpSpacing.xs),
              child: Center(child: _searchOnButton(l10n)),
            );
          }
          // The last row asks for the next page when it is built, so a
          // short first page still fills up without scrolling.
          if (!_loading) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => unawaited(_loadMore()),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(WpSpacing.sm),
            child: Center(
              child: Semantics(
                label: l10n.modelLibraryHfLoading,
                child: const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The languages a row names: the searched ones first, at most three, then
  /// "+n"; "multilingual" when the repo says only that.
  String? _hitLanguages(BuildContext context, HfModelHit hit) {
    final l10n = L10n.of(context);
    final codes = hfDisplayLanguages(hit.languages, _query.languages);
    if (codes.isEmpty) {
      return hit.multilingual ? l10n.modelLibraryHfMultilingual : null;
    }
    const shown = 3;
    final names = _languageList(context, codes.take(shown).toList());
    return codes.length > shown
        ? l10n.modelLibraryHfLanguagesMore(names, codes.length - shown)
        : names;
  }

  // -------------------------------------------------------------------------
  // Detail
  // -------------------------------------------------------------------------

  Widget _detail(BuildContext context, HfModelHit hit) {
    final l10n = L10n.of(context);
    final body = TextStyle(
      fontSize: WpTypography.body,
      color: WpColors.textSecondary,
    );
    final options = _options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WpTextLink(
          testID: 'model-library-hf-back',
          label: l10n.modelLibraryHfBack,
          onPressed: _close,
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          hit.repoId,
          key: const ValueKey('model-library-hf-detail-name'),
          style: body.copyWith(
            fontWeight: FontWeight.w600,
            color: WpColors.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xxs),
        Wrap(
          spacing: WpSpacing.xxs,
          runSpacing: WpSpacing.xxs,
          children: [
            WpAccentBadge(
              label: l10n.modelLibraryHfNotVerified,
              tone: WpAccentBadgeTone.highlight,
            ),
            _LicenseBadge(hit: hit),
          ],
        ),
        const SizedBox(height: WpSpacing.xxs),
        Text(l10n.modelLibraryHfLicenseNote, style: body),
        const SizedBox(height: WpSpacing.xxs),
        WpTextLink(
          testID: 'model-library-hf-open-page',
          label: l10n.modelLibraryHfOpenPage,
          kind: WpLinkKind.web,
          onPressed: () => unawaited(openExternalUrl(context, hit.pageUrl)),
        ),
        const SizedBox(height: WpSpacing.sm),
        if (hit.gated)
          _Message(
            testId: 'model-library-hf-gated',
            text: l10n.modelLibraryAddErrorGated,
          )
        else if (_resolving)
          Semantics(
            liveRegion: true,
            label: l10n.modelLibraryHfResolving,
            child: const LinearProgressIndicator(),
          )
        else if (_resolveError case final e?)
          _Message(
            testId: 'model-library-hf-resolve-error',
            text: switch (e) {
              HfResolveError.gated => l10n.modelLibraryAddErrorGated,
              HfResolveError.notFound ||
              HfResolveError.pathMissing => l10n.modelLibraryAddErrorNotFound,
              _ => l10n.modelLibraryAddErrorNetwork,
            },
            action: WpButton(
              testId: 'model-library-hf-resolve-retry',
              label: l10n.modelLibraryHfRetry,
              variant: WpButtonVariant.secondary,
              onPressed: () => unawaited(_openHit(hit)),
            ),
          )
        else if (options != null && options.isEmpty)
          _Message(
            testId: 'model-library-hf-no-file',
            text: l10n.modelLibraryHfNoFile,
          )
        else if (options != null) ...[
          Text(
            l10n.modelLibraryHfChooseFile,
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Semantics(
            container: true,
            label: l10n.modelLibraryHfChooseFile,
            child: Wrap(
              spacing: WpSpacing.xxs,
              children: [
                for (final (i, o) in options.indexed)
                  WpFilterChip(
                    testId: 'model-library-hf-option-$i',
                    label: [
                      o.label,
                      if (o.sizeBytes > 0) formatByteSize(o.sizeBytes),
                      ?_fitText(l10n, o.fit),
                    ].join(' · '),
                    isActive: identical(_picked, o),
                    onTap: () => _pick(o),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The language filter's entries; [pick] opens the language dialog.
enum _LanguageChoice { mine, all, custom, pick }

bool _sameLanguages(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);

String _sizeLabel(L10n l10n, HfSizeFilter f) => switch (f) {
  HfSizeFilter.fitsDevice => l10n.modelLibraryHfSizeFitsDevice,
  HfSizeFilter.any => l10n.modelLibraryHfSizeAny,
  _ => l10n.modelLibraryHfSizeUpTo(formatByteSize(f.maxBytes!)),
};

String _sortLabel(L10n l10n, HfSearchSort s) => switch (s) {
  HfSearchSort.downloads => l10n.modelLibraryHfSortDownloads,
  HfSearchSort.likes => l10n.modelLibraryHfSortLikes,
  HfSearchSort.lastModified => l10n.modelLibraryHfSortRecent,
};

String? _fitText(L10n l10n, DeviceFit fit) => switch (fit) {
  DeviceFit.comfortable => l10n.modelLibraryHfFitComfortable,
  DeviceFit.tight => l10n.modelLibraryHfFitTight,
  DeviceFit.tooBig => l10n.modelLibraryHfFitTooBig,
  DeviceFit.unknown => null,
};

String _errorText(L10n l10n, HfSearchException e) => switch (e.error) {
  HfSearchError.offline ||
  HfSearchError.noConsent => l10n.modelLibraryHfOffline,
  HfSearchError.rateLimited => l10n.modelLibraryHfRateLimited(
    ((e.retryAfter?.inSeconds ?? 300) / 60).ceil().clamp(1, 60),
  ),
  HfSearchError.badResponse => l10n.modelLibraryHfError,
};

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.onAgree});
  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      key: const ValueKey('model-library-hf-consent'),
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: WpColors.surfaceMutedFill,
        borderRadius: WpRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.modelLibraryHfConsentTitle,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.modelLibraryHfConsentBody,
            style: TextStyle(
              fontSize: WpTypography.body,
              color: WpColors.textSecondary,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          WpButton(
            testId: 'model-library-hf-consent-accept',
            label: l10n.modelLibraryHfConsentAccept,
            variant: WpButtonVariant.secondary,
            onPressed: onAgree,
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.modelLibraryHfConsentDeclineHint,
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.testId, required this.text, this.action});
  final String testId;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    identifier: testId,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          key: ValueKey(testId),
          style: TextStyle(
            fontSize: WpTypography.body,
            color: WpColors.textSecondary,
          ),
        ),
        if (action case final a?) ...[const SizedBox(height: WpSpacing.sm), a],
      ],
    ),
  );
}

class _LicenseBadge extends StatelessWidget {
  const _LicenseBadge({required this.hit});
  final HfModelHit hit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final license = hit.license ?? '';
    return switch (hit.licenseKind) {
      HfLicenseKind.open => WpAccentBadge(
        label: l10n.modelLibraryAddLicense(license),
        tone: WpAccentBadgeTone.muted,
      ),
      HfLicenseKind.custom => WpAccentBadge(
        label: l10n.modelLibraryHfLicenseCustom(license),
        tone: WpAccentBadgeTone.highlight,
      ),
      HfLicenseKind.nonCommercial => WpAccentBadge(
        label: l10n.modelLibraryHfLicenseNonCommercial(license),
        tone: WpAccentBadgeTone.highlight,
      ),
      HfLicenseKind.unknown => WpAccentBadge(
        label: l10n.modelLibraryHfLicenseUnknown,
        tone: WpAccentBadgeTone.highlight,
      ),
    };
  }
}

class _HitRow extends StatefulWidget {
  const _HitRow({
    super.key,
    required this.hit,
    required this.ramMB,
    required this.languageNames,
    required this.onOpen,
  });
  final HfModelHit hit;
  final int? ramMB;
  final String? languageNames;
  final VoidCallback onOpen;

  @override
  State<_HitRow> createState() => _HitRowState();
}

/// One hit: name with its owner (two repos of the same name stay apart),
/// then what matters to a writer: size and whether it fits, languages,
/// popularity; license and gate as badges.
class _HitRowState extends State<_HitRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locale = Localizations.localeOf(context).toString();
    final hit = widget.hit;
    final count = NumberFormat.compact(locale: locale);
    final bytes = hit.estimatedBytes;
    final size = bytes == null
        ? l10n.modelLibraryHfSizeUnknown
        : l10n.modelLibraryHfSizeFrom(
            '${hit.sizeExact ? '' : '≈ '}${formatByteSize(bytes)}',
          );
    final fit = bytes == null
        ? null
        : _fitText(l10n, deviceFitFor(bytes, widget.ramMB));
    final facts = [
      fit == null ? size : '$size, $fit',
      ?widget.languageNames,
      l10n.modelLibraryHfDownloads(count.format(hit.downloads)),
      l10n.modelLibraryHfLikes(count.format(hit.likes)),
      if (hit.lastModified case final d?)
        l10n.modelLibraryHfUpdated(DateFormat.yMMMd(locale).format(d)),
    ].join(' · ');
    final muted = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    return Semantics(
      button: true,
      identifier: 'model-library-hf-hit',
      child: FocusableActionDetector(
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onOpen,
          child: WpListTileSurface(
            variant: WpListTileVariant.panel,
            isHovered: _hovered,
            isFocused: _focused,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.xs,
                vertical: WpSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          hit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: WpTypography.body,
                            fontWeight: FontWeight.w600,
                            color: WpColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: WpSpacing.xxs),
                      Flexible(
                        child: Text(
                          l10n.modelLibraryHfBy(hit.author),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    facts,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: WpSpacing.xxs,
                    runSpacing: 2,
                    children: [
                      _LicenseBadge(hit: hit),
                      if (hit.gated)
                        WpAccentBadge(
                          label: l10n.modelLibraryHfGated,
                          tone: WpAccentBadgeTone.muted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
