/// Block-list rule for auto-paste (AUF-1): normalisation, the per-platform
/// matching rule, and fail-closed behaviour with an unknown target.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';
import 'package:whispaste/services/paste/auto_paste_blocklist.dart';

/// The block list reads the same target evidence as the app-profile resolver
/// (one source): [targetEvidenceFromNativeId] wraps the native identifier.
AutoPasteBlocklistVerdict _verdict(
  String raw,
  String? target, {
  bool isMacOS = false,
}) => evaluateAutoPasteBlocklist(
  raw: raw,
  target: targetEvidenceFromNativeId(target),
  isMacOS: isMacOS,
);

void main() {
  group('normalisation', () {
    test('entries drop a trailing .exe and ignore case and blanks', () {
      expect(
        parseAutoPasteBlocklist(
          ' 1Password.EXE , , Terminal.exe,com.apple.Terminal ',
        ),
        {'1password', 'terminal', 'com.apple.terminal'},
      );
    });

    test('an empty or blank list parses to nothing', () {
      expect(parseAutoPasteBlocklist(''), isEmpty);
      expect(parseAutoPasteBlocklist(' , '), isEmpty);
    });
  });

  group('empty list (today behaviour)', () {
    test('never blocks, even with an unknown target', () {
      expect(_verdict('', null), AutoPasteBlocklistVerdict.allowed);
      expect(
        _verdict('  ', null, isMacOS: true),
        AutoPasteBlocklistVerdict.allowed,
      );
    });
  });

  group('fail-closed (AUF-1)', () {
    test('a set list with an unknown target is not allowed', () {
      for (final target in <String?>[null, '', '   ']) {
        for (final isMacOS in [true, false]) {
          expect(
            _verdict('1password', target, isMacOS: isMacOS),
            AutoPasteBlocklistVerdict.targetUnknown,
            reason: 'target=$target macOS=$isMacOS',
          );
        }
      }
    });
  });

  group('Windows: exact match after normalisation', () {
    test('notepad.exe blocks the exe name notepad and no other app', () {
      expect(
        _verdict('notepad.exe', 'notepad'),
        AutoPasteBlocklistVerdict.listed,
      );
      expect(
        _verdict('notepad.exe', 'wordpad'),
        AutoPasteBlocklistVerdict.allowed,
      );
    });

    test('a blocked 1password stops auto-paste for 1Password.EXE', () {
      expect(
        _verdict('1password', '1Password.EXE'),
        AutoPasteBlocklistVerdict.listed,
      );
    });

    test('an entry with .exe matches the bare exe name', () {
      expect(
        _verdict('1password.exe', '1password'),
        AutoPasteBlocklistVerdict.listed,
      );
    });

    test('no prefix match on Windows', () {
      expect(
        _verdict('1password', '1password-helper'),
        AutoPasteBlocklistVerdict.allowed,
      );
    });

    test('an unlisted app is allowed', () {
      expect(
        _verdict('1password', 'notepad'),
        AutoPasteBlocklistVerdict.allowed,
      );
    });
  });

  group('Linux WM_CLASS: exact match after normalisation', () {
    test('a WM_CLASS value on the list is blocked', () {
      expect(
        _verdict('1password', '1Password'),
        AutoPasteBlocklistVerdict.listed,
      );
    });

    test('a different WM_CLASS is allowed', () {
      expect(
        _verdict('1password', 'gnome-terminal'),
        AutoPasteBlocklistVerdict.allowed,
      );
    });
  });

  group('macOS: exact or dot-bounded prefix on the bundle id', () {
    test('com.1password matches com.1password.1password', () {
      expect(
        _verdict('com.1password', 'com.1password.1password', isMacOS: true),
        AutoPasteBlocklistVerdict.listed,
      );
    });

    test('the prefix must end at a dot boundary', () {
      expect(
        _verdict('com.1password', 'com.1passwordx.app', isMacOS: true),
        AutoPasteBlocklistVerdict.allowed,
      );
    });

    test('the prefix rule is macOS only', () {
      expect(
        _verdict('com.1password', 'com.1password.1password'),
        AutoPasteBlocklistVerdict.allowed,
      );
    });
  });

  group('one target source for block list and app profiles', () {
    test('a profile rule and a block-list entry match the same Windows '
        'target', () {
      const profile = AppProfile(
        id: 'p',
        name: 'Notes',
        rules: [AppMatchRule(identifier: 'notepad.exe')],
      );
      final target = targetEvidenceFromNativeId('notepad');

      expect(
        resolveAppProfile(
          choice: const ProfileChoiceAutomatic(),
          profiles: const [profile],
          target: target,
        ).profile,
        same(profile),
      );
      expect(
        evaluateAutoPasteBlocklist(
          raw: 'notepad.exe',
          target: target,
          isMacOS: false,
        ),
        AutoPasteBlocklistVerdict.listed,
      );
    });

    test('no native identifier is no target evidence', () {
      expect(targetEvidenceFromNativeId(null), isNull);
      expect(targetEvidenceFromNativeId('  '), isNull);
    });
  });

  group('capability and short-prefix warning (AUF-1, GS-075)', () {
    test('target detection is available on macOS and Windows', () {
      expect(
        autoPasteTargetDetectionAvailable(isLinux: false, linuxStatus: null),
        isTrue,
      );
    });

    test('on Linux it follows the session focus status (V1 Wayland)', () {
      expect(
        autoPasteTargetDetectionAvailable(
          isLinux: true,
          linuxStatus: LinuxFocusStatus.available,
        ),
        isTrue,
      );
      for (final missing in [
        LinuxFocusStatus.gnomeExtensionMissing,
        LinuxFocusStatus.unsupported,
      ]) {
        expect(
          autoPasteTargetDetectionAvailable(
            isLinux: true,
            linuxStatus: missing,
          ),
          isFalse,
          reason: missing.name,
        );
      }
    });

    test('a status still being probed shows no hint yet', () {
      expect(
        autoPasteTargetDetectionAvailable(isLinux: true, linuxStatus: null),
        isTrue,
      );
    });

    test('entries without a dot are reported, dotted bundle ids are not', () {
      expect(
        autoPasteShortPrefixEntries('Safari, com.apple.Terminal, 1password'),
        ['safari', '1password'],
      );
      expect(autoPasteShortPrefixEntries('com.apple.Terminal'), isEmpty);
      expect(autoPasteShortPrefixEntries(' , '), isEmpty);
    });
  });

  group('Linux placeholder example', () {
    // The example in the block-list field must name an app the rule really
    // blocks. The native X11 lookup reports the WM_CLASS instance name, so
    // GNOME Terminal is `gnome-terminal-server`, not `gnome-terminal`.
    for (final lang in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
      test(
        '$lang: every Linux placeholder entry blocks its own WM_CLASS name',
        () {
          final arb =
              jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                  as Map<String, dynamic>;
          final placeholder =
              arb['settingsAutoPasteBlocklistPlaceholderLinux'] as String;
          final entries = placeholder
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty);
          expect(entries, isNotEmpty);
          expect(
            entries.contains('gnome-terminal-server'),
            isTrue,
            reason: 'the example names the WM_CLASS instance, not the binary',
          );
          expect(
            evaluateAutoPasteBlocklist(
              raw: placeholder,
              target: targetEvidenceFromNativeId('gnome-terminal-server'),
              isMacOS: false,
            ),
            AutoPasteBlocklistVerdict.listed,
          );
        },
      );
    }
  });
}
