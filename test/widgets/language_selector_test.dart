import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/locale_native_name.dart';
import 'package:whispaste/widgets/language_selector.dart';

import '../fixtures/test_helpers.dart';

/// Public-API tests for [LanguageSelector].
///
/// Slice 06 deliberately drops the segmented pill row plus flag icons and
/// replaces it with a compact dropdown widget that renders the native
/// language name only.  These tests pin the contract Slice 07 will reuse
/// in the settings InterfaceSection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanguageSelector', () {
    testWidgets('closed state shows the native name for the current locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(LanguageSelector(currentLocale: 'de', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deutsch'), findsOneWidget);
    });

    testWidgets('closed state never renders an SvgPicture flag', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(LanguageSelector(currentLocale: 'en', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('opened state shows native names for every supported locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(LanguageSelector(currentLocale: 'de', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      for (final locale in L10n.supportedLocales) {
        expect(
          find.text(localeNativeName(locale)),
          findsWidgets,
          reason:
              'native label missing in expanded dropdown for '
              '${locale.languageCode}',
        );
      }
    });

    testWidgets('opened state renders no SvgPicture flags', (tester) async {
      await tester.pumpWidget(
        makeTestable(LanguageSelector(currentLocale: 'de', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('opened state highlights the active entry', (tester) async {
      await tester.pumpWidget(
        makeTestable(LanguageSelector(currentLocale: 'de', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      // The active entry exposes itself via a stable key for test access;
      // any non-active entry uses a different key.  This guarantees the
      // highlight is observable from the widget tree, independent of the
      // exact decoration style.
      expect(
        find.byKey(const ValueKey('LanguageSelector.active.de')),
        findsOneWidget,
        reason: 'active entry must be tagged with a stable key for highlight',
      );
      expect(
        find.byKey(const ValueKey('LanguageSelector.active.en')),
        findsNothing,
      );
    });

    testWidgets('tapping English fires onChanged with "en"', (tester) async {
      String? captured;
      await tester.pumpWidget(
        makeTestable(
          LanguageSelector(
            currentLocale: 'de',
            onChanged: (code) => captured = code,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      expect(captured, 'en');
    });

    testWidgets('tapping Hebrew fires onChanged with "he"', (tester) async {
      String? captured;
      await tester.pumpWidget(
        makeTestable(
          LanguageSelector(
            currentLocale: 'de',
            onChanged: (code) => captured = code,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();

      await tester.tap(find.text(localeNativeName(const Locale('he'))).last);
      await tester.pumpAndSettle();

      expect(captured, 'he');
    });

    testWidgets(
      'unknown current locale falls back to the first supported locale label',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            LanguageSelector(currentLocale: 'zz', onChanged: (_) {}),
          ),
        );
        await tester.pumpAndSettle();

        // Defensive fallback: should display the first supportedLocales entry
        // as a stand-in rather than throw.
        final fallback = localeNativeName(L10n.supportedLocales.first);
        expect(find.text(fallback), findsOneWidget);
      },
    );
  });
}
