/// The Help hub (ticket): the rail's Hilfe entry opens the handbook first, with
/// the support, introduction and diagnostics sections one tab away. Deep links
/// pick the tab, and a chapter slug picks the handbook chapter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/feedback/feedback_type.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';

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

/// Records every page switch, so a test can see where a button leads.
class _RecordingPages extends ActivePageNotifier {
  _RecordingPages(this._log);

  final List<String> _log;

  @override
  void setPage(String id) {
    _log.add(id);
    super.setPage(id);
  }
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

/// Five tabs do not all fit the default test window; the tab bar scrolls.
Future<void> _tapTab(WidgetTester tester, String id) async {
  final tab = find.byKey(ValueKey('help-hub-tab-$id'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
}

Future<void> _openDiagnostics(WidgetTester tester) async {
  await _tapTab(tester, 'diagnostics');
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  group('Help hub tabs', () {
    testWidgets('the handbook is the first tab and is shown by default', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('manual-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('support-page')), findsNothing);
    });

    testWidgets('the five tabs have stable ids and carry the labels', (
      tester,
    ) async {
      await _pump(tester);

      for (final id in const [
        'manual',
        'intro',
        'feedback',
        'support',
        'diagnostics',
      ]) {
        expect(
          find.byKey(ValueKey('help-hub-tab-$id')),
          findsOneWidget,
          reason: id,
        );
      }
    });

    testWidgets('tapping the support tab shows the support content', (
      tester,
    ) async {
      await _pump(tester);

      await _tapTab(tester, 'support');
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
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-row-general-sponsor-chip')),
        findsOneWidget,
      );
    });

    testWidgets('the feedback tab holds every way to reach the team (#395)', (
      tester,
    ) async {
      await _pump(tester);

      await _tapTab(tester, 'feedback');
      await tester.pumpAndSettle();

      for (final row in const [
        'help-contact-form',
        'help-report-problem',
        'advanced-ideas',
        'help-contact-mail',
      ]) {
        expect(
          find.byKey(ValueKey('settings-row-$row')),
          findsOneWidget,
          reason: row,
        );
      }
      expect(find.byKey(const ValueKey('support-page')), findsNothing);
    });

    testWidgets('the introduction tab holds the replay rows', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('help-hub-tab-intro')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-row-advanced-onboarding-again')),
        findsOneWidget,
      );
    });

    testWidgets('the diagnostics tab holds the copy and the issue rows', (
      tester,
    ) async {
      await _pump(tester);

      await _tapTab(tester, 'diagnostics');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-row-help-diagnostics')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-row-help-report-issue')),
        findsOneWidget,
      );
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

    testWidgets('the diagnostics tab links to the privacy policy and imprint', (
      tester,
    ) async {
      await _pump(tester);

      await _tapTab(tester, 'diagnostics');
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

      // The button itself confirms; no toast is involved.
      // Let the confirmation end so no timer is left pending.
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

    test('a gather that never finishes ends in the fallback (#1635)', () {
      fakeAsync((async) {
        String? result;
        diagnosticsReportWithin(
          () => Completer<String>().future,
          en,
        ).then((r) => result = r);
        async.elapse(kDiagnosticsReportTimeout - const Duration(seconds: 1));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(result, contains(en.helpDiagnosticsTimedOut));
        expect(result, startsWith('WhisPaste v'));
      });
    });

    test('a gather in time is passed through unchanged', () async {
      expect(await diagnosticsReportWithin(() async => 'report', en), 'report');
    });

    testWidgets('the Diagnose tab has a Legal section with the two links', (
      tester,
    ) async {
      await _pump(tester);
      await _openDiagnostics(tester);

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

  group('contact card', () {
    testWidgets('its button opens the contact form', (tester) async {
      final pages = <String>[];
      await tester.pumpWidget(
        makeTestable(
          const HelpPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(_OnboardedSettings.new),
            helpTargetProvider.overrideWith(() => _Target(null)),
            activePageProvider.overrideWith(() => _RecordingPages(pages)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('help-contact-button')));
      await tester.pumpAndSettle();

      expect(pages, ['feedback']);
    });
  });

  group('feedback tab hand-over (#395)', () {
    Future<List<String>> pumpFeedbackTab(WidgetTester tester) async {
      final pages = <String>[];
      await tester.pumpWidget(
        makeTestable(
          const HelpPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(_OnboardedSettings.new),
            helpTargetProvider.overrideWith(
              () => _Target(const HelpTarget(tab: HelpTab.feedback)),
            ),
            activePageProvider.overrideWith(() => _RecordingPages(pages)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return pages;
    }

    for (final (id, preset) in const [
      ('help-feedback-button', null),
      ('help-problem-button', FeedbackType.problem),
      ('help-idea-button', FeedbackType.idea),
    ]) {
      testWidgets('$id opens the form with preset $preset', (tester) async {
        final pages = await pumpFeedbackTab(tester);
        await tester.ensureVisible(find.byKey(ValueKey(id)));
        await tester.tap(find.byKey(ValueKey(id)));
        await tester.pumpAndSettle();

        expect(pages, ['feedback']);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HelpPage)),
        );
        expect(container.read(feedbackPresetTypeProvider), preset);
      });
    }

    testWidgets('the contact address starts a mail', (tester) async {
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final opened = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            final url = (call.arguments as Map)['url'] as String?;
            if (call.method == 'launch' && url != null) opened.add(url);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null),
      );
      await pumpFeedbackTab(tester);
      final link = find.byKey(const ValueKey('help-contact-mail-link'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(opened, ['mailto:$kContactEmail']);
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
        'help-hub-tab-feedback',
        'help-hub-tab-support',
        'help-hub-tab-diagnostics',
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      await _tapTab(tester, 'feedback');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('help-feedback-button'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('diagnostics public note, busy status and translations', () {});
}
