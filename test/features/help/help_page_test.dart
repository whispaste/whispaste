/// The Help hub (WP-78): the rail's Hilfe entry opens the handbook first, with
/// the support, introduction and diagnostics sections one tab away. Deep links
/// pick the tab, and a chapter slug picks the handbook chapter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import '../../fixtures/test_helpers.dart';

late L10n en;

/// Onboarding finished, so the introduction row is shown on its tab.
class _OnboardedSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    onboarding: AppSettings.defaults.onboarding.copyWith(
      onboardingCompleted: true,
    ),
  );
}

/// Opens the hub on [target] the way a deep link does.
class _Target extends HelpTargetNotifier {
  _Target(this._target);

  final HelpTarget? _target;

  @override
  HelpTarget? build() => _target;
}

/// A report that never probes the host, so the tests stay hermetic.
const String _fixtureReport = 'WhisPaste fixture\nOS: test\n--- log ---';

Future<void> _pump(
  WidgetTester tester, {
  HelpTarget? target,
  Future<String> Function()? report,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const HelpPage(),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(_OnboardedSettings.new),
        helpTargetProvider.overrideWith(() => _Target(target)),
        helpReportProvider.overrideWith(
          (ref) => report ?? () async => _fixtureReport,
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDiagnostics(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('help-hub-tab-diagnostics')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  group('Help hub tabs', () {
    testWidgets('the page brings no title of its own (the shell shows it)', (
      tester,
    ) async {
      await _pump(tester);

      // A second WpPageHeader here rendered "Hilfe" twice under the shell's.
      expect(find.byType(WpPageHeader), findsNothing);
    });

    testWidgets('the handbook is the first tab and is shown by default', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('manual-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('support-page')), findsNothing);
    });

    testWidgets('the four tabs have stable ids and carry the labels', (
      tester,
    ) async {
      await _pump(tester);

      for (final id in const ['manual', 'intro', 'support', 'diagnostics']) {
        expect(
          find.byKey(ValueKey('help-hub-tab-$id')),
          findsOneWidget,
          reason: id,
        );
      }
      expect(find.text(en.helpTabManual), findsOneWidget);
      expect(find.text(en.helpTabIntro), findsOneWidget);
      expect(find.text(en.helpTabSupport), findsOneWidget);
      expect(find.text(en.helpTabDiagnostics), findsOneWidget);
    });

    testWidgets('tapping the support tab shows the support content', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-support')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('support-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('manual-view')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-row-advanced-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-advanced-github-star')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-advanced-ideas')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-general-sponsor-chip')),
        findsOneWidget,
      );
    });

    testWidgets('the introduction tab holds the replay rows', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-intro')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-row-advanced-onboarding-again')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-advanced-feature-spotlights')),
        findsOneWidget,
      );
    });

    testWidgets('the diagnostics tab holds the copy and the issue rows', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-diagnostics')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-row-help-diagnostics')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-help-report-issue')),
        findsOneWidget,
      );
      expect(find.text(en.aboutCopyDebugInfo), findsOneWidget);
      expect(find.text(en.aboutReportIssue), findsOneWidget);
    });
  });

  group('deep links', () {
    testWidgets('a target tab opens that tab', (tester) async {
      await _pump(tester, target: const HelpTarget(tab: HelpTab.diagnostics));

      expect(
        find.byKey(const ValueKey('settings-row-help-diagnostics')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('manual-view')), findsNothing);
    });

    testWidgets('a chapter target opens the handbook on that chapter', (
      tester,
    ) async {
      await _pump(
        tester,
        target: const HelpTarget(tab: HelpTab.manual, chapterSlug: 'privacy'),
      );

      final privacy = manualChapters.firstWhere((c) => c.slug == 'privacy');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('manual-chapter-title')))
            .data,
        privacy.title(en),
      );
    });

    testWidgets('a query target opens the handbook search with that query '
        '(UIA-SET-11)', (tester) async {
      await _pump(
        tester,
        target: HelpTarget(tab: HelpTab.manual, query: en.manualC12Title),
      );

      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('manual-search')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        en.manualC12Title,
      );
      expect(
        find.byKey(const ValueKey('manual-chapter-privacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('manual-chapter-shortcuts')),
        findsNothing,
      );
    });

    testWidgets('the target is consumed, so a later visit starts afresh', (
      tester,
    ) async {
      await _pump(tester, target: const HelpTarget(tab: HelpTab.support));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HelpPage)),
      );
      expect(container.read(helpTargetProvider), isNull);
    });
  });

  group('handbook search', () {
    testWidgets('the search narrows the chapter list', (tester) async {
      await _pump(tester);

      await tester.enterText(
        find.byKey(const ValueKey('manual-search')),
        en.manualC12Title,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('manual-chapter-privacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('manual-chapter-shortcuts')),
        findsNothing,
      );
    });

    testWidgets('a query without a hit says so', (tester) async {
      await _pump(tester);

      await tester.enterText(
        find.byKey(const ValueKey('manual-search')),
        'zqxj-no-such-text',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('manual-search-empty')), findsOneWidget);
      expect(find.text(en.manualSearchEmpty), findsOneWidget);
    });
  });

  group('handbook search keys and legal links', () {
    testWidgets('Escape empties the search and shows every chapter again', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(
        find.byKey(const ValueKey('manual-search')),
        en.manualC12Title,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('manual-chapter-${manualChapters.first.slug}')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The first chapter is always built; a lazily built row further down the
      // list is not a reliable witness in a short window.
      expect(
        find.byKey(ValueKey('manual-chapter-${manualChapters.first.slug}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('manual-search-empty')), findsNothing);
    });

    // UIA-HLP-05: each "Open" button names its target for screen readers.
    testWidgets('each open button names its target (UIA-HLP-05)', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-diagnostics')));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(en.actionOpenNamed(en.aboutPrivacyPolicy)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(en.actionOpenNamed(en.aboutReportIssue)),
        findsOneWidget,
      );
    });

    testWidgets('the diagnostics tab links to the privacy policy and imprint', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-diagnostics')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-help-privacy-policy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-help-imprint')),
        findsOneWidget,
      );
    });
  });

  group('diagnostics transparency and copy', () {
    testWidgets('the preview shows the report text before anything is copied', (
      tester,
    ) async {
      await _pump(tester);
      await _openDiagnostics(tester);

      expect(
        find.byKey(const ValueKey('help-diagnostics-preview-text')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('help-diagnostics-preview')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('help-diagnostics-preview-text')),
            )
            .data,
        _fixtureReport,
      );
      expect(find.text(en.aboutDiagnosticsContentsDesc), findsOneWidget);
      expect(find.text(en.aboutDiagnosticsPreviewHide), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('help-diagnostics-preview')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-diagnostics-preview-text')),
        findsNothing,
      );
    });

    testWidgets('copy puts the same report on the clipboard', (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pump(tester);
      await _openDiagnostics(tester);
      await tester.tap(find.byKey(const ValueKey('help-diagnostics-copy')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(copied, _fixtureReport);
    });

    // UIA-HLP-07: the confirmation is a toast, not only a button label change.
    testWidgets('a successful copy also shows a success toast (UIA-HLP-07)', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pump(tester);
      await _openDiagnostics(tester);
      await tester.tap(find.byKey(const ValueKey('help-diagnostics-copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // One text is the button label, the other the toast message.
      expect(find.text(en.aboutCopied), findsNWidgets(2));
      // Let the toast dismiss so no timer is left pending.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a failing gather copies a localized, redacted fallback', (
      tester,
    ) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pump(
        tester,
        report: () async => throw Exception('api_key=abc123xyz failed'),
      );
      await _openDiagnostics(tester);
      await tester.tap(find.byKey(const ValueKey('help-diagnostics-copy')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(copied, contains(en.aboutDiagnosticsIncomplete('')));
      expect(copied, isNot(contains('abc123xyz')));
      expect(copied, contains('<redacted>'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
    });

    test(
      'the fallback block removes secrets and the user name from the error',
      () {
        final home = Platform.environment['HOME'];
        final error = Exception(
          'token=abc123xyz in ${home ?? '/Users/someone'}/Library',
        );
        final block = diagnosticsFallbackReport(error, en);

        expect(block, startsWith('WhisPaste v'));
        expect(block, isNot(contains('abc123xyz')));
        if (home != null && home.isNotEmpty) {
          expect(block, isNot(contains(home)));
        }
        expect(block, contains(en.aboutDiagnosticsIncomplete('')));
        expect(block, contains('<redacted>'));
      },
    );

    testWidgets('the Diagnose tab has a Legal section with the two links', (
      tester,
    ) async {
      await _pump(tester);
      await _openDiagnostics(tester);

      expect(find.text(en.helpLegalTitle), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings-help-imprint'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings-help-privacy-policy'),
        findsOneWidget,
      );
    });
  });

  group('semantics identifiers', () {
    testWidgets('tabs and the new Help buttons carry identifiers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      for (final id in const [
        'help-hub-tab-manual',
        'help-hub-tab-intro',
        'help-hub-tab-support',
        'help-hub-tab-diagnostics',
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      await tester.tap(find.byKey(const ValueKey('help-hub-tab-support')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('help-feedback-button'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('diagnostics public note, busy status and translations', () {
    testWidgets('the diagnostics tab warns that issues are public', (
      tester,
    ) async {
      await _pump(tester);
      await _openDiagnostics(tester);
      expect(find.text(en.helpDiagnosticsPublicNote), findsOneWidget);
    });

    testWidgets('while the report is built a spinner and label show', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gate = Completer<String>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, report: () => gate.future);
      await _openDiagnostics(tester);

      expect(find.text(en.helpDiagnosticsBuilding), findsNothing);
      await tester.tap(find.byKey(const ValueKey('help-diagnostics-copy')));
      await tester.pump();

      expect(find.text(en.helpDiagnosticsBuilding), findsOneWidget);
      expect(find.bySemanticsLabel(en.helpDiagnosticsBuilding), findsOneWidget);

      gate.complete(_fixtureReport);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(en.helpDiagnosticsBuilding), findsNothing);
      handle.dispose();
    });

    test('Legal is translated in Spanish and Portuguese', () {
      expect(lookupL10n(const Locale('es')).helpLegalTitle, 'Aviso legal');
      expect(
        lookupL10n(const Locale('pt')).helpLegalTitle,
        'Informações legais',
      );
    });

    test('the new texts are translated in every language', () {
      for (final code in ['de', 'es', 'pt', 'ru', 'he']) {
        final l = lookupL10n(Locale(code));
        expect(
          l.helpDiagnosticsPublicNote,
          isNot(en.helpDiagnosticsPublicNote),
        );
        expect(l.helpDiagnosticsBuilding, isNot(en.helpDiagnosticsBuilding));
        expect(l.tabsScrollBack, isNot(en.tabsScrollBack));
        expect(l.tabsScrollForward, isNot(en.tabsScrollForward));
      }
    });
  });
}
