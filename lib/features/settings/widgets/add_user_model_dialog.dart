/// "Add own model" in the model library (#1514, #1789): an address (a
/// Hugging Face repo or one HTTPS file) or files from this computer, picked
/// or dropped. Before anything is fetched the user sees what will be added,
/// confirms the source's terms and every host outside the fixed list, and
/// the free space is checked ([preflightUserModel]). The dialog returns the
/// draft; the page starts the addition, so its progress shows in the list.
///
/// The first way is the Hugging-Face-Suche (#2047, [HfModelSearchPanel]):
/// after a one-time consent it finds runnable models on huggingface.co and
/// hands the picked file to the same draft, terms and install path.
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/text/byte_size.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/free_disk_space.dart';
import '../../../services/path_service.dart' show userModelsDir;
import '../../../services/user_models/user_model.dart';
import '../../../services/user_models/user_model_installer.dart';
import '../../../services/user_models/user_models_provider.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_consent_checkbox.dart';
import '../../../widgets/wp_segmented_selector.dart';
import '../../../widgets/wp_text_field.dart';
import 'hf_model_search_panel.dart';

/// Opens the dialog for [purpose] and returns the draft to add, or null.
Future<UserModelDraft?> showAddUserModelDialog(
  BuildContext context, {
  required UserModelPurpose purpose,
}) => showWpFormDialog<UserModelDraft>(
  context: context,
  builder: (ctx, animation) =>
      _AddUserModelDialog(animation: animation, purpose: purpose),
);

/// The sentence for a [UserModelSourceError].
String userModelSourceErrorText(
  L10n l10n,
  UserModelSourceError error,
) => switch (error) {
  UserModelSourceError.address => l10n.modelLibraryAddErrorAddress,
  UserModelSourceError.notFound => l10n.modelLibraryAddErrorNotFound,
  UserModelSourceError.gated => l10n.modelLibraryAddErrorGated,
  UserModelSourceError.network => l10n.modelLibraryAddErrorNetwork,
  UserModelSourceError.noModel => l10n.modelLibraryAddErrorNoModel,
  UserModelSourceError.wrongPurpose => l10n.modelLibraryAddErrorWrongPurpose,
  UserModelSourceError.needsAllFiles => l10n.modelLibraryAddErrorNeedsAllFiles,
};

class _AddUserModelDialog extends ConsumerStatefulWidget {
  const _AddUserModelDialog({required this.animation, required this.purpose});

  final Animation<double> animation;
  final UserModelPurpose purpose;

  @override
  ConsumerState<_AddUserModelDialog> createState() =>
      _AddUserModelDialogState();
}

/// The two ways in: search Hugging Face, or an address / files.
enum _AddMode { search, address }

class _AddUserModelDialogState extends ConsumerState<_AddUserModelDialog> {
  final TextEditingController _address = TextEditingController();
  _AddMode _mode = _AddMode.search;
  UserModelDraft? _draft;
  String? _error;
  bool _busy = false;
  bool _terms = false;
  bool _hosts = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _show(UserModelSourceResult result) {
    final l10n = L10n.of(context);
    setState(() {
      _busy = false;
      _terms = false;
      _hosts = false;
      switch (result) {
        case UserModelSourceOk(:final draft):
          _draft = draft;
          _error = null;
        case UserModelSourceFailed(:final error):
          _draft = null;
          _error = userModelSourceErrorText(l10n, error);
      }
    });
  }

  void _onSearchDraft(UserModelDraft? draft) => setState(() {
    _draft = draft;
    _error = null;
    _terms = false;
    _hosts = false;
  });

  void _switchMode(_AddMode mode) => setState(() {
    _mode = mode;
    _draft = null;
    _error = null;
    _terms = false;
    _hosts = false;
  });

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await prepareDraftFromAddress(
      _address.text,
      purpose: widget.purpose,
      confirmedHosts: ref.read(userModelsProvider).confirmedHosts,
    );
    if (mounted) _show(result);
  }

  Future<void> _pickFiles() async {
    final files = await openFiles();
    if (files.isEmpty || !mounted) return;
    _show(
      prepareDraftFromFiles([
        for (final f in files) f.path,
      ], purpose: widget.purpose),
    );
  }

  void _onDrop(DropDoneDetails details) {
    final paths = [for (final f in details.files) f.path];
    if (paths.isEmpty) return;
    _show(prepareDraftFromFiles(paths, purpose: widget.purpose));
  }

  Future<void> _add() async {
    final draft = _draft;
    if (draft == null) return;
    final notifier = ref.read(userModelsProvider.notifier);
    final known = ref.read(userModelsProvider).confirmedHosts;
    final toConfirm = hostsToConfirm(draft, known);
    final free = await ref.read(freeDiskSpaceProbeProvider)(userModelsDir());
    final issue = preflightUserModel(
      draft,
      termsConfirmed: _terms,
      confirmedHosts: {...known, if (_hosts) ...toConfirm},
      freeBytes: free,
    );
    if (!mounted) return;
    final l10n = L10n.of(context);
    switch (issue) {
      case null:
        notifier.confirmHosts(toConfirm);
        Navigator.of(context).pop(draft);
      case NotEnoughSpace(:final neededBytes, :final freeBytes):
        setState(
          () => _error = l10n.modelLibraryAddErrorSpace(
            formatByteSize(neededBytes),
            formatByteSize(freeBytes),
          ),
        );
      case TermsNotConfirmed() || HostsNotConfirmed():
        // The button stays off until both are ticked; nothing to say here.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final draft = _draft;
    final hosts = draft == null
        ? const <String>{}
        : hostsToConfirm(draft, ref.watch(userModelsProvider).confirmedHosts);
    final ready = draft != null && _terms && (hosts.isEmpty || _hosts);
    final body = TextStyle(
      fontSize: WpTypography.body,
      color: WpColors.textSecondary,
    );

    return DropTarget(
      onDragDone: _onDrop,
      child: WpFormDialogShell(
        animation: widget.animation,
        title: widget.purpose == UserModelPurpose.speech
            ? l10n.modelLibraryAddTitleSpeech
            : l10n.modelLibraryAddTitleSmartMode,
        subtitle: _mode == _AddMode.search
            ? l10n.modelLibraryHfSubtitle
            : l10n.modelLibraryAddSubtitle,
        size: _mode == _AddMode.search
            ? WpDialogSize.wide
            : WpDialogSize.standard,
        fields: [
          WpSegmentedChoice<_AddMode>(
            options: [
              WpSegmentOption(
                value: _AddMode.search,
                label: l10n.modelLibraryHfTabSearch,
              ),
              WpSegmentOption(
                value: _AddMode.address,
                label: l10n.modelLibraryHfTabAddress,
              ),
            ],
            selected: _mode,
            onChanged: _switchMode,
          ),
          const SizedBox(height: WpSpacing.md),
          if (_mode == _AddMode.search)
            HfModelSearchPanel(purpose: widget.purpose, onDraft: _onSearchDraft)
          else ...[
            WpTextField(
              key: const ValueKey('model-library-add-address'),
              controller: _address,
              variant: WpTextFieldVariant.form,
              hintText: l10n.modelLibraryAddAddressHint,
              semanticsLabel: l10n.modelLibraryAddAddressLabel,
              autocorrect: false,
              autofocus: true,
              onSubmitted: (_) => unawaited(_check()),
            ),
            const SizedBox(height: WpSpacing.sm),
            Wrap(
              spacing: WpSpacing.buttonGap,
              runSpacing: WpSpacing.xs,
              children: [
                WpButton(
                  testId: 'model-library-add-check',
                  label: l10n.modelLibraryAddCheck,
                  variant: WpButtonVariant.secondary,
                  isLoading: _busy,
                  onPressed: _busy ? null : () => unawaited(_check()),
                ),
                WpButton(
                  testId: 'model-library-add-files',
                  label: l10n.modelLibraryAddFiles,
                  variant: WpButtonVariant.ghost,
                  onPressed: _busy ? null : () => unawaited(_pickFiles()),
                ),
              ],
            ),
            const SizedBox(height: WpSpacing.xs),
            Text(
              l10n.modelLibraryAddDropHint,
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: WpColors.textMuted,
              ),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: WpSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                key: const ValueKey('model-library-add-error'),
                style: TextStyle(
                  fontSize: WpTypography.body,
                  color: WpColors.error,
                ),
              ),
            ),
          ],
          if (draft != null) ...[
            const SizedBox(height: WpSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                [
                  draft.name,
                  if (draft.totalBytes > 0) formatByteSize(draft.totalBytes),
                  if (draft.license case final license?)
                    l10n.modelLibraryAddLicense(license),
                ].join(' · '),
                key: const ValueKey('model-library-add-summary'),
                style: body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
            Text(l10n.modelLibraryAddNotVerifiedNote, style: body),
            const SizedBox(height: WpSpacing.sm),
            WpConsentCheckbox(
              key: const ValueKey('model-library-add-terms'),
              value: _terms,
              onChanged: (v) => setState(() => _terms = v),
              label: l10n.modelLibraryAddTerms,
              explanation: l10n.modelLibraryAddTermsExplanation,
            ),
            if (hosts.isNotEmpty)
              WpConsentCheckbox(
                key: const ValueKey('model-library-add-hosts'),
                value: _hosts,
                onChanged: (v) => setState(() => _hosts = v),
                label: l10n.modelLibraryAddHosts(hosts.join(', ')),
                explanation: l10n.modelLibraryAddHostsExplanation,
              ),
          ],
        ],
        actions: [
          WpDialogAction<UserModelDraft>(
            label: l10n.actionCancel,
            testId: 'model-library-add-cancel',
            role: WpDialogActionRole.cancel,
          ),
          WpDialogAction<UserModelDraft>(
            label: l10n.modelLibraryAddConfirm,
            testId: 'model-library-add-confirm',
            role: WpDialogActionRole.deliberate,
            enabled: ready,
            onPressed: () => unawaited(_add()),
          ),
        ],
      ),
    );
  }
}
