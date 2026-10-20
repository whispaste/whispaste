import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/features/help/manual/manual_model.dart';

/// The Linux auto-paste section of the handbook (chapter 14) is split per
/// install format, and every command is its own block so it can be copied.
void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  ManualSection sectionTitled(String title) {
    final chapter = manualChapters.singleWhere(
      (c) => c.sections.any((s) => s.heading(l10n) == title),
      orElse: () => throw StateError('no chapter has a "$title" section'),
    );
    return chapter.sections.singleWhere((s) => s.heading(l10n) == title);
  }

  test('Linux auto-paste has one section per install format', () {
    final flatpak = sectionTitled('Flatpak');
    final snap = sectionTitled('Snap');
    final appImage = sectionTitled('AppImage');

    expect(
      flatpak.blocks.whereType<ManualNotice>(),
      hasLength(1),
      reason: 'The read-rights warning is a notice, not body text.',
    );
    expect(snap.blocks, hasLength(3));
    expect(appImage.blocks, hasLength(1));
  });

  test('the udev command is a block of its own in the Flatpak section', () {
    final texts = [
      for (final block in sectionTitled('Flatpak').blocks)
        if (block is ManualCode) block.text(l10n),
    ];
    expect(texts, contains(l10n.manualC14S15Cmd));
    expect(l10n.manualC14S15Cmd, startsWith('sudo udevadm'));
  });

  test('the snap command is a block of its own in the Snap section', () {
    final texts = [
      for (final block in sectionTitled('Snap').blocks)
        if (block is ManualCode) block.text(l10n),
    ];
    expect(texts, contains(l10n.manualC14S15SnapCmd));
    expect(l10n.manualC14S15SnapCmd, 'sudo snap connect whispaste:uinput');
  });
}
