import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/selection_edit/selection_edit_prompt.dart';
import 'package:whispaste/services/selection_edit/selection_edit_service.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  for (final locale in L10n.supportedLocales) {
    final l10n = lookupL10n(locale);

    group('edit selection l10n (${locale.languageCode})', () {
      test('every error code has its own overlay message', () {
        final codes = [
          'selection_edit_no_engine',
          'selection_edit_local_unavailable',
          'selection_edit_unsupported',
          ...SelectionEditFailure.values.map((f) => f.errorCode),
        ];
        for (final code in codes) {
          final message = localizeRecordingError(l10n, code);
          expect(message, isNot(l10n.errorGeneric), reason: code);
          expect(message.trim(), isNotEmpty, reason: code);
        }
      });

      test('missing local engine library reuses the settings hint', () {
        expect(
          localizeRecordingError(l10n, 'selection_edit_local_unavailable'),
          l10n.smartModeLocalUnavailable,
        );
      });

      test('done message names the replacement', () {
        expect(
          doneMessageFor('paste', l10n, target: RecordingTarget.selectionEdit),
          l10n.overlayDoneSelectionEdit,
        );
      });

      test('every quick-action keyword the overlay hint names is '
          'recognized', () {
        final hint = l10n.overlaySelectionEditHint;
        final list = hint.substring(hint.lastIndexOf(':') + 1);
        final keywords = list.split('·').map((w) => w.trim()).toList();
        expect(keywords, hasLength(3), reason: hint);
        expect(keywords.map(selectionEditQuickActionFor).toSet(), {
          SelectionEditQuickAction.shorten,
          SelectionEditQuickAction.improve,
          SelectionEditQuickAction.translate,
        });
      });
    });
  }
}
