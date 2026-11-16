import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';

/// One hint per package format on the Linux Auto-Paste page. Each hint names
/// the step that format needs, or says it works without one.
void main() {
  final de = lookupL10n(const Locale('de'));
  final en = lookupL10n(const Locale('en'));

  test('each format maps to its own hint text', () {
    expect(
      linuxPasteHintText(de, LinuxPackageFormat.native),
      de.onboardingPasteLinuxNative,
    );
    expect(
      linuxPasteHintText(de, LinuxPackageFormat.flatpak),
      de.onboardingPasteLinuxFlatpak,
    );
    expect(
      linuxPasteHintText(de, LinuxPackageFormat.snap),
      de.onboardingPasteLinuxSnap,
    );
    expect(
      linuxPasteHintText(de, LinuxPackageFormat.appimage),
      de.onboardingPasteLinuxAppImage,
    );
    expect(
      {for (final f in LinuxPackageFormat.values) linuxPasteHintText(de, f)},
      hasLength(LinuxPackageFormat.values.length),
      reason: 'the four hints must be distinct',
    );
  });

  test('the Flatpak hint names the --device=all permission', () {
    expect(
      linuxPasteHintText(en, LinuxPackageFormat.flatpak),
      contains('--device=all'),
    );
  });

  test('the Snap hint gives the exact connect command', () {
    expect(
      linuxPasteHintText(en, LinuxPackageFormat.snap),
      contains('sudo snap connect whispaste:uinput'),
    );
  });

  test(
    'the AppImage hint shows the udev setup, session access only (R-02)',
    () {
      final text = linuxPasteHintText(en, LinuxPackageFormat.appimage);
      expect(text, contains('71-whispaste-uinput.rules'));
      expect(text, contains('signed-in session'));
      expect(text, contains('administrator rights'));
      expect(
        text,
        contains('sudo udevadm control --reload-rules && sudo udevadm trigger'),
      );
      // R-02 (4a): the rule no longer opens the device to the input group, and
      // joining that group is no longer offered (it also grants reading every
      // keyboard).
      expect(text, isNot(contains('usermod')));
      expect(text, isNot(contains('input group')));
    },
  );

  test('the native hint asks for consent, never "works automatically"', () {
    final text = linuxPasteHintText(en, LinuxPackageFormat.native);
    expect(text, isNot(contains('works automatically')));
    expect(text, contains('Allow'));
  });

  test('the override seam decides which format the page describes', () {
    debugLinuxPackageFormatOverride = LinuxPackageFormat.snap;
    addTearDown(() => debugLinuxPackageFormatOverride = null);
    expect(linuxPasteFormatForOnboarding(), LinuxPackageFormat.snap);
  });

  group('LinuxPasteHint widget', () {
    Finder hintById(LinuxPackageFormat f) => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.identifier ==
              'onboarding-autopaste-linux-hint-${f.name}',
    );

    Future<void> pumpHint(WidgetTester tester, LinuxPackageFormat? format) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LinuxPasteHint(format: format, l10n: en),
            ),
          ),
        ),
      );
    }

    for (final format in LinuxPackageFormat.values) {
      testWidgets('shows only the ${format.name} hint for that format', (
        tester,
      ) async {
        await pumpHint(tester, format);
        expect(hintById(format), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(
                find.descendant(
                  of: hintById(format),
                  matching: find.byType(SelectableText),
                ),
              )
              .data,
          linuxPasteHintText(en, format),
        );
        for (final other in LinuxPackageFormat.values.where(
          (f) => f != format,
        )) {
          expect(hintById(other), findsNothing);
        }
      });
    }

    testWidgets('an undetectable install shows the hint for every format', (
      tester,
    ) async {
      await pumpHint(tester, null);
      for (final format in LinuxPackageFormat.values) {
        expect(hintById(format), findsOneWidget);
      }
    });
  });
}
