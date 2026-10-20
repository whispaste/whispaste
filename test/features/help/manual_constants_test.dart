import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/ltr_isolate.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/features/help/manual/manual_model.dart';
import 'package:whispaste/features/settings/sections/smart_mode_section.dart'
    show kSmartModeRamWarningThresholdMB;
import 'package:whispaste/services/hardware_info_service.dart' show kMinRamMB;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

/// Decimal separator per locale, as NumberFormat writes it.
const _decimal = {
  'de': ',',
  'en': '.',
  'es': ',',
  'pt': ',',
  'ru': ',',
  'he': '.',
};

String _gb(num gigabytes, String locale) =>
    gigabytes.toStringAsFixed(1).replaceAll('.', _decimal[locale]!);

String _blockText(ManualBlock block, L10n l) => switch (block) {
  ManualParagraph(:final text) => text(l),
  ManualBullets(:final items) => items.map((item) => item(l)).join(' '),
  ManualTip(:final text) => text(l),
  ManualNotice(:final text) => text(l),
  ManualLabelled(:final label, :final text) => '${label(l)} ${text(l)}',
  ManualCode(:final text) => text(l),
};

String _handbook(L10n l) => [
  for (final chapter in manualChapters)
    for (final section in chapter.sections)
      for (final block in section.blocks) _blockText(block, l),
].join('\n');

void main() {
  final loaded = <String, L10n>{};

  setUpAll(() async {
    for (final code in _decimal.keys) {
      loaded[code] = await L10n.delegate.load(Locale(code));
    }
  });

  for (final code in _decimal.keys) {
    test('handbook figures in $code match the code constants', () {
      final text = _handbook(loaded[code]!);

      // RAM gate: the user-facing minimum is 8192 MB, shown as "8 GB".
      expect(text, contains('${kMinRamMB ~/ 1024} GB'));

      // Smart Mode warns below 8192 MB and downloads the model's size.
      expect(text, contains('${kSmartModeRamWarningThresholdMB ~/ 1024} GB'));
      expect(
        text,
        contains(
          '${_gb(smartModeModel.sizeBytes / (1024 * 1024 * 1024), code)} GB',
        ),
      );

      // STT model sizes, as the download screens label them.
      expect(text, contains(formatModelSizeLabel(sttModels.first.sizeBytes)));
      expect(text, contains(formatModelSizeLabel(sttModels.last.sizeBytes)));
      expect(
        text,
        contains(formatModelSizeLabel(parakeetDownloadBytes(gpuWanted: false))),
      );
    });
  }

  test('RAM sentence shows the 8 GB minimum in de and en', () {
    expect(
      _handbook(loaded['de']!),
      contains('mindestens ${ltrIsolate('8 GB')} Arbeitsspeicher'),
    );
    expect(
      _handbook(loaded['en']!),
      contains('at least ${ltrIsolate('8 GB')} of memory'),
    );
  });

  test('English handbook uses a point, never a decimal comma', () {
    expect(_handbook(loaded['en']!), isNot(contains('7,5')));
    expect(_handbook(loaded['en']!), isNot(contains(RegExp(r'\d,\d GB'))));
  });
}
