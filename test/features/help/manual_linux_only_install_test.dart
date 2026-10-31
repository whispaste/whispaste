import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/features/help/manual/manual_model.dart';

/// The GStreamer install command is an apt command for Debian and Ubuntu.
/// Its paragraph and its code block belong to Linux only, so macOS and
/// Windows readers never see a command that cannot run there (PAR-044).
void main() {
  test(
    'the apt install block and its paragraph are shown on Linux only',
    () async {
      final l10n = await L10n.delegate.load(const Locale('de'));
      final blocks = [
        for (final chapter in manualChapters)
          for (final section in chapter.sections) ...section.blocks,
      ];

      final hasCommand = blocks.any(
        (b) => b is ManualCode && b.id == 'gstreamer-libav-install',
      );
      final hasParagraph = blocks.any(
        (b) => b is ManualParagraph && b.text(l10n) == l10n.manualC09S1B3,
      );

      expect(
        hasCommand,
        Platform.isLinux,
        reason: 'The apt command is a Linux block (PAR-044).',
      );
      expect(
        hasParagraph,
        Platform.isLinux,
        reason:
            'The Linux paragraph about the decoder is a Linux block (PAR-044).',
      );
    },
  );
}
