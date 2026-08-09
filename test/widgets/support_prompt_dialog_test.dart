/// Widget tests for [WpSupportPromptWatcher] — verifies the dialog renders the
/// reused support copy/buttons and resolves via the correct notifier method
/// per action.
///
/// Mirrors `test/widgets/review_prompt_dialog_test.dart`'s structure.
///
/// Covers:
///  AC1  Dialog shows the support title/body/CTAs after the shared post-
///       recording delay elapses.
///  AC2  GitHub Sponsors button launches [kGitHubSponsorsUrl] and calls
///       `markLinkOpened`.
///  AC3  Ko-fi button launches [kKofiUrl] and calls `markLinkOpened`.
///  AC4  Dismiss ("never ask again") resolves the prompt without launching
///       any URL, and calls `dismiss` (not `markLinkOpened`).
///  AC5  When [SupportPromptState.kind] is `recurringFollowUp`, the dialog
///       shows the distinct recurring-follow-up copy instead of the initial
///       ask's copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/prompt_timing.dart';
import 'package:whispaste/services/support_prompt_service.dart';
import 'package:whispaste/widgets/support_prompt_dialog.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifier
// ---------------------------------------------------------------------------

/// Stub that lets tests drive [shouldShowPrompt] without touching
/// SharedPreferences or the history database.
class _FakeSupportPromptNotifier extends SupportPromptNotifier {
  bool dismissCalled = false;
  bool markLinkOpenedCalled = false;

  @override
  SupportPromptState build() =>
      const SupportPromptState(shouldShowPrompt: false);

  /// Flips [shouldShowPrompt] to `true` (with the given [kind]) so
  /// [WpSupportPromptWatcher]'s listener fires and starts the shared
  /// post-recording delay.
  void triggerShow({SupportPromptKind kind = SupportPromptKind.initial}) =>
      state = SupportPromptState(shouldShowPrompt: true, kind: kind);

  @override
  Future<void> dismiss() async {
    dismissCalled = true;
    state = state.copyWith(shouldShowPrompt: false);
  }

  @override
  Future<void> markLinkOpened() async {
    markLinkOpenedCalled = true;
    state = state.copyWith(shouldShowPrompt: false);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Pumps [WpSupportPromptWatcher] and advances time past
/// [kPostRecordingPromptDelay] so the dialog is fully visible and animated in.
Future<_FakeSupportPromptNotifier> _showDialog(
  WidgetTester tester, {
  required L10n l10n,
  SupportPromptKind kind = SupportPromptKind.initial,
}) async {
  final notifier = _FakeSupportPromptNotifier();

  await tester.pumpWidget(
    makeTestable(
      const WpSupportPromptWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [supportPromptProvider.overrideWith(() => notifier)],
    ),
  );
  await tester.pump(); // initial build, ref.listen registered

  notifier.triggerShow(kind: kind);
  await tester.pump(); // state change propagated, delay timer started
  await tester.pump(kPostRecordingPromptDelay); // timer fires → _showDialog()
  await tester.pumpAndSettle(); // showGeneralDialog + 300 ms animation

  return notifier;
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (_) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  testWidgets('renders the support title, body and both CTA buttons (AC1)', (
    tester,
  ) async {
    await _showDialog(tester, l10n: l10n);

    expect(find.text(l10n.aboutSupportTitle), findsOneWidget);
    expect(find.text(l10n.aboutSupportDescription), findsOneWidget);
    expect(find.text(l10n.aboutGitHubSponsors), findsOneWidget);
    expect(find.text(l10n.aboutKofi), findsOneWidget);
    expect(find.text(l10n.reviewPromptNever), findsOneWidget);
  });

  testWidgets('GitHub Sponsors button launches kGitHubSponsorsUrl and calls '
      'markLinkOpened, not dismiss (AC2)', (tester) async {
    String? capturedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            capturedUrl = (call.arguments as Map)['url'] as String?;
          }
          return true;
        });

    final notifier = await _showDialog(tester, l10n: l10n);

    await tester.tap(find.text(l10n.aboutGitHubSponsors));
    await tester.pumpAndSettle();

    expect(capturedUrl, kGitHubSponsorsUrl);
    expect(notifier.markLinkOpenedCalled, isTrue);
    expect(notifier.dismissCalled, isFalse);
  });

  testWidgets('Ko-fi button launches kKofiUrl and calls markLinkOpened, not '
      'dismiss (AC3)', (tester) async {
    String? capturedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            capturedUrl = (call.arguments as Map)['url'] as String?;
          }
          return true;
        });

    final notifier = await _showDialog(tester, l10n: l10n);

    await tester.tap(find.text(l10n.aboutKofi));
    await tester.pumpAndSettle();

    expect(capturedUrl, kKofiUrl);
    expect(notifier.markLinkOpenedCalled, isTrue);
    expect(notifier.dismissCalled, isFalse);
  });

  testWidgets('dismiss ("never ask again") calls dismiss (not '
      'markLinkOpened) without launching any URL (AC4)', (tester) async {
    String? capturedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            capturedUrl = (call.arguments as Map)['url'] as String?;
          }
          return true;
        });

    final notifier = await _showDialog(tester, l10n: l10n);

    await tester.tap(find.text(l10n.reviewPromptNever));
    await tester.pumpAndSettle();

    expect(capturedUrl, isNull);
    expect(notifier.dismissCalled, isTrue);
    expect(notifier.markLinkOpenedCalled, isFalse);
    expect(notifier.state.shouldShowPrompt, isFalse);
  });

  testWidgets('shows the distinct recurring follow-up copy when kind is '
      'recurringFollowUp (AC5)', (tester) async {
    await _showDialog(
      tester,
      l10n: l10n,
      kind: SupportPromptKind.recurringFollowUp,
    );

    expect(find.text(l10n.supportPromptRecurringTitle), findsOneWidget);
    expect(find.text(l10n.supportPromptRecurringDescription), findsOneWidget);
    expect(find.text(l10n.aboutSupportTitle), findsNothing);
    expect(find.text(l10n.aboutSupportDescription), findsNothing);
  });
}
