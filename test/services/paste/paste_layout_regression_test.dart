/// Layout-regression tests for the Unicode direct-type paste fallback
/// (ticket 09 — `.scratch/fluidvoice-catchup/issues/09-layout-regressionstests-paste.md`).
///
/// Scope, per the ticket:
/// - Targets ONLY the direct-type fallback (`Paster.typeText`, and the
///   fallback branch inside `DesktopPaster.paste` that retries via typing
///   when the native paste shortcut doesn't land). The primary
///   clipboard-paste path is explicitly NOT under test here — it is
///   inherently layout-independent (plain text on the OS clipboard) and is
///   already covered by `paster_test.dart`.
/// - The matrix covers US, DE/QWERTZ, RU, and HE (RTL) sample dictation
///   text, each built around [_layoutRiskPunctuation] — the same
///   punctuation set `win_layout_label.dart`'s `_scanCodeByPhysicalKey`
///   documents as layout-sensitive at the virtual-key level for the
///   Windows hotkey recorder (#108). This is the exact character set the
///   ticket calls out as "already known to be layout-dependent risk."
/// - No real hardware/keyboard layout is involved, mirroring
///   `hotkey_key_resolver_test.dart`: these tests pin what crosses the
///   `DesktopPasteController` boundary via a fake controller, not the
///   native keystroke synthesis itself.
///
/// Finding for this ticket: no layout-dependent gap exists on the Dart
/// side of the fallback. `DesktopPaster.typeText` (and `paste`'s fallback
/// branch) forward `text` to `DesktopPasteController.typeText` completely
/// unmodified — there is no per-character/per-layout lookup table in Dart
/// that could get a physical position wrong the way the pre-#108 hotkey
/// code did. The actual typing mechanism lives natively and already
/// avoids that bug class by construction, not by a per-layout table:
/// - macOS posts raw Unicode codepoints via
///   `CGEventKeyboardSetUnicodeString` (`DesktopPasteHost.swift`'s
///   `postUnicodeString`) — it never touches a virtual-key/layout table,
///   so umlauts, Cyrillic, Hebrew, and ASCII punctuation all survive
///   identically regardless of the active layout.
/// - Windows and Linux route the fallback through the exact same
///   clipboard + Ctrl+V primitive as the primary paste path
///   (`SendPasteShortcut`'s raw `VK_CONTROL`/`'V'` injection on Windows;
///   uinput `KEY_LEFTCTRL`/`KEY_V` on Linux) — the same mechanism the
///   ticket itself calls "inherently layout-independent" for the primary
///   path, reused rather than duplicated for the fallback.
///
/// These tests pin that invariant (byte-for-byte passthrough, regardless
/// of script) so a future change can't reintroduce a per-layout table on
/// either side of the Dart/native boundary without breaking a test.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paster.dart';

/// Punctuation physical keys whose Windows virtual-key assignment is known
/// to vary by keyboard layout — mirrors
/// `win_layout_label.dart`'s `_scanCodeByPhysicalKey` table (the exact set
/// #108 fixed for the hotkey recorder). Embedded in every locale sample
/// below so a regression that drops/mangles any of them is caught.
const List<String> _layoutRiskPunctuation = [
  '`',
  '-',
  '=',
  '[',
  ']',
  '\\',
  ';',
  "'",
  ',',
  '.',
  '/',
];

/// One realistic dictation sample per layout, each containing every
/// character in [_layoutRiskPunctuation] plus script letters representative
/// of that layout/locale.
const Map<String, String> _layoutSamples = {
  'US (QWERTY)':
      r"It's 9:30 [maybe] = ok - let's go; `quote`, path\here / that's all.",
  'DE (QWERTZ)':
      r"Ähm, sie's fährt [später] = ok - los; `Zitat`, pfad\hier / grüße.",
  'RU (ЙЦУКЕН)':
      r"Привет, это тест [скоро] = ладно - идём; `цитата', путь\сюда / всё.",
  // Hebrew (RTL). Storage/transport is still a plain UTF-16 Dart String —
  // there is no bidi reordering to account for at this layer; direction is
  // purely a rendering concern handled elsewhere.
  'HE (RTL)': r"שלום, זה מבחן [אולי] = טוב - קדימה; `ציטוט', נתיב\לכאן / הכל.",
};

class _FakeController implements DesktopPasteController {
  int pasteCalls = 0;
  int typeCalls = 0;
  String? lastTypedText;
  NativePasteResult pasteResult = const NativePasteResult(
    status: NativePasteStatus.success,
  );
  NativePasteResult typeResult = const NativePasteResult(
    status: NativePasteStatus.success,
  );

  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls++;
    return pasteResult;
  }

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async {
    typeCalls++;
    lastTypedText = text;
    return typeResult;
  }

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async => false;

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardContent;
  setUp(() {
    clipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardContent = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardContent == null) return null;
              return <String, dynamic>{'text': clipboardContent};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group(
    'layout-risk punctuation set matches the hotkey-recorder fix (#108)',
    () {
      test('every scan-code-sensitive punctuation char is covered by every '
          'locale sample', () {
        for (final entry in _layoutSamples.entries) {
          for (final char in _layoutRiskPunctuation) {
            expect(
              entry.value.contains(char),
              isTrue,
              reason: '${entry.key} sample is missing layout-risk char "$char"',
            );
          }
        }
      });
    },
  );

  group('Paster.typeText — direct-type fallback layout matrix', () {
    for (final entry in _layoutSamples.entries) {
      test('${entry.key}: forwards the text to the native controller byte-for'
          '-byte unchanged (no per-layout lookup in Dart)', () async {
        final controller = _FakeController();
        final paster = DesktopPaster(controller);

        final outcome = await paster.typeText(
          entry.value,
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        expect(outcome, PasteOutcome.success);
        expect(controller.typeCalls, 1);
        expect(
          controller.lastTypedText,
          entry.value,
          reason:
              'typeText must not transform ${entry.key} text at all — '
              'the native side (CGEventKeyboardSetUnicodeString on '
              'macOS, clipboard-reuse on Windows/Linux) is what makes '
              'this layout-independent, not a Dart-side lookup',
        );
        // Explicit char-by-char audit of the layout-risk punctuation set,
        // pinning the exact bug class #108 fixed for hotkeys (a lookup
        // table that silently substitutes the wrong physical/logical
        // key per layout) as impossible here too, one char at a time.
        for (final char in _layoutRiskPunctuation) {
          expect(
            controller.lastTypedText!.contains(char),
            isTrue,
            reason: '${entry.key}: "$char" was dropped/altered by the fallback',
          );
        }
      });
    }
  });

  group(
    'DesktopPaster.paste — fallback-on-failure layout matrix '
    '(primary clipboard path is explicitly NOT under test — see file doc)',
    () {
      for (final entry in _layoutSamples.entries) {
        test(
          '${entry.key}: when the native paste shortcut fails, the '
          'macOS/Windows retry types the identical text; Linux (no '
          'direct-type fallback) reports the original failure untouched',
          () async {
            final controller = _FakeController()
              ..pasteResult = const NativePasteResult(
                status: NativePasteStatus.postFailed,
              );
            final paster = DesktopPaster(controller);

            final outcome = await paster.paste(
              entry.value,
              const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
            );

            expect(controller.pasteCalls, 1);
            if (Platform.isMacOS || Platform.isWindows) {
              expect(outcome, PasteOutcome.success);
              expect(controller.typeCalls, 1);
              expect(controller.lastTypedText, entry.value);
            } else {
              expect(outcome, PasteOutcome.failed);
              expect(controller.typeCalls, 0);
            }
          },
        );
      }
    },
  );

  group('requiresRealPaste — multi-line gating is script-independent', () {
    for (final entry in _layoutSamples.entries) {
      test('${entry.key}: a multi-line dictation in this script still blocks '
          'the typing fallback on every platform (chat-UI "submit" risk from '
          'a literal Return keydown — see requiresRealPaste doc)', () async {
        final multiline = '${entry.value}\n${entry.value}';
        expect(requiresRealPaste(multiline), isTrue);

        final controller = _FakeController()
          ..pasteResult = const NativePasteResult(
            status: NativePasteStatus.postFailed,
          );
        final paster = DesktopPaster(controller);

        final outcome = await paster.paste(
          multiline,
          const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
        );

        // Multi-line text never falls back to typing, regardless of
        // platform or script.
        expect(controller.typeCalls, 0);
        expect(outcome, PasteOutcome.failed);
      });

      test('${entry.key}: single-line text (no \\n/\\r) does not trip the '
          'multi-line guard', () {
        expect(requiresRealPaste(entry.value), isFalse);
      });
    }
  });
}
