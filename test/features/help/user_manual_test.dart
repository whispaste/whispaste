import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/features/help/manual/manual_model.dart';
import 'package:whispaste/features/help/manual/user_manual_view.dart';

import '../../fixtures/test_helpers.dart';

const _locales = ['de', 'en', 'es', 'pt', 'he', 'ru'];
const _wide = Size(1280, 800);

String _probeHeading(L10n l) => 'Probe heading';
String _probeBody(L10n l) => 'Probe paragraph';

final _loaded = <String, L10n>{};

Future<void> _pumpManual(
  WidgetTester tester, {
  required String locale,
  Size size = _wide,
}) {
  return tester.pumpWidget(
    makeTestable(
      const Scaffold(body: UserManualView()),
      size: size,
      locale: Locale(locale),
    ),
  );
}

/// Visible text of one block, used by the guard test.
String _blockText(ManualBlock block, L10n l10n) => switch (block) {
  ManualParagraph(:final text) => text(l10n),
  ManualBullets(:final items) => items.map((item) => item(l10n)).join(' '),
  ManualTip(:final text) => text(l10n),
  ManualNotice(:final text) => text(l10n),
  ManualLabelled(:final label, :final text) => '${label(l10n)} ${text(l10n)}',
  ManualCode(:final text) => text(l10n),
};

void main() {
  setUpAll(() async {
    for (final code in _locales) {
      _loaded[code] = await L10n.delegate.load(Locale(code));
    }
  });

  group('UserManualView', () {
    late L10n en;

    setUpAll(() {
      en = _loaded['en']!;
    });

    testWidgets('every chapter can be selected and shows its title', (
      tester,
    ) async {
      await _pumpManual(tester, locale: 'en');

      for (final chapter in manualChapters) {
        final row = find.byKey(ValueKey('manual-chapter-${chapter.slug}'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('manual-chapter-content')),
            matching: find.text(chapter.title(en)),
          ),
          findsOneWidget,
          reason: 'chapter ${chapter.slug} should show its title',
        );
      }
    });
  });

  group('search and shortcut reference (HLP-04, HLP-06)', () {
    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('manual-search')),
          matching: find.byType(EditableText),
        ),
        query,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the search announces the number of matching chapters (UIA-HLP-06)',
      (tester) async {
        await _pumpManual(tester, locale: 'en');
        await search(tester, 'zzqx');

        expect(find.text('No chapters found'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
          findsWidgets,
        );
      },
    );

    testWidgets('the shortcut reference names the F1 help key (UIA-HLP-04)', (
      tester,
    ) async {
      await _pumpManual(tester, locale: 'en');
      await search(tester, 'F1 opens help');

      expect(find.text('F1 opens help.'), findsOneWidget);
    });
  });

  group('handbook content guard', () {
    test('there are 17 chapters with unique slugs', () {
      expect(manualChapters, hasLength(17));
      final slugs = manualChapters.map((c) => c.slug).toSet();
      expect(slugs, hasLength(manualChapters.length));
    });

    for (final code in _locales) {
      test('every chapter, section and block has text in $code', () {
        final l10n = _loaded[code]!;

        for (final chapter in manualChapters) {
          final title = chapter.title(l10n);
          expect(title.trim(), isNotEmpty, reason: '${chapter.slug} title');
          expect(chapter.sections, isNotEmpty, reason: chapter.slug);

          for (final section in chapter.sections) {
            final heading = section.heading(l10n);
            expect(
              heading.trim(),
              isNotEmpty,
              reason: '${chapter.slug} heading',
            );
            expect(section.blocks, isNotEmpty, reason: heading);

            for (final block in section.blocks) {
              final text = _blockText(block, l10n);
              expect(
                text.trim(),
                isNotEmpty,
                reason: '${chapter.slug}: $heading',
              );
              expect(
                text,
                isNot(contains('{k')),
                reason: 'unfilled placeholder in ${chapter.slug}: $heading',
              );
            }
          }
        }
      });
    }
  });

  testWidgets('handbook body text follows a theme switch', (tester) async {
    addTearDown(() => WpColors.activate(wpLightColors));
    final chapters = <ManualChapter>[
      ManualChapter(
        slug: 'probe',
        title: (_) => 'Probe chapter',
        sections: const <ManualSection>[
          ManualSection(
            heading: _probeHeading,
            blocks: <ManualBlock>[ManualParagraph(_probeBody)],
          ),
        ],
      ),
    ];
    Widget view() => makeTestable(
      Scaffold(body: UserManualView(chapters: chapters)),
      size: _wide,
      locale: const Locale('en'),
    );
    Color bodyColor() =>
        tester.widget<Text>(find.text('Probe paragraph')).style!.color!;

    WpColors.activate(wpLightColors);
    await tester.pumpWidget(view());
    expect(bodyColor(), wpLightColors.textPrimary);

    WpColors.activate(wpDarkColors);
    await tester.pumpWidget(view());
    expect(bodyColor(), wpDarkColors.textPrimary);
  });
}
