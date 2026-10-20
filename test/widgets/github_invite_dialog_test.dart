/// Widget tests for [WpGitHubInviteWatcher]: buttons, outcomes, telemetry
/// labels, and the conditions under which the invitation must stay silent
/// (recording running, another prompt owning the display window).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/github_invite_service.dart';
import 'package:whispaste/services/prompt_display_arbiter.dart';
import 'package:whispaste/services/prompt_timing.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/github_invite_dialog.dart';

import '../fixtures/test_helpers.dart';
import '../test_helpers/nudge_gate_open.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Records every outcome the watcher asks for, without touching prefs.
class _FakeInviteNotifier extends GitHubInviteNotifier {
  final List<String> calls = [];

  @override
  GitHubInviteState build() =>
      const GitHubInviteState(channel: DeployChannel.store);

  void triggerShow() => state = state.copyWith(shouldShowInvite: true);

  @override
  void deferInvite() {
    calls.add('defer');
    state = state.copyWith(shouldShowInvite: false);
  }

  @override
  Future<void> recordImpression({DateTime? now}) async =>
      calls.add('impression');

  @override
  Future<void> markStarOpened() async {
    calls.add('starOpened');
    state = state.copyWith(shouldShowInvite: false);
  }

  @override
  Future<void> dismiss({required bool permanent}) async {
    calls.add(permanent ? 'dismiss:permanent' : 'dismiss:later');
    state = state.copyWith(shouldShowInvite: false);
  }
}

/// Telemetry that keeps the event bodies it sends.
TelemetryService _capturingTelemetry(List<Map<String, String>> sent) {
  return TelemetryService(
    client: MockClient((request) async {
      sent.add(request.bodyFields);
      return http.Response('', 200);
    }),
    endpointUrl: 'https://telemetry.test',
    siteId: 1,
    consentGranted: true,
    dntActive: false,
  );
}

Future<
  ({
    _FakeInviteNotifier notifier,
    List<Map<String, String>> sent,
    List<String> launched,
  })
>
_pump(
  WidgetTester tester, {
  bool macOs = false,
  RecordingPhase phase = RecordingPhase.idle,
  bool occupied = false,
}) async {
  githubInviteIsMacOsOverride = macOs;
  final sent = <Map<String, String>>[];
  final launched = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_launcherChannel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
  final notifier = _FakeInviteNotifier();
  final arbiter = PromptDisplayArbiter();
  if (occupied) {
    arbiter.tryClaim(PromptOwner.review, close: () {});
  }
  final telemetry = _capturingTelemetry(sent);

  await tester.pumpWidget(
    makeTestable(
      const WpGitHubInviteWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [
        githubInviteProvider.overrideWith(() => notifier),
        recordingPhaseProvider.overrideWith((ref) => phase),
        promptDisplayArbiterProvider.overrideWithValue(arbiter),
        telemetryProvider.overrideWithValue(telemetry),
        nudgeGateOpenOverride(),
      ],
    ),
  );
  await tester.pump();
  notifier.triggerShow();
  await tester.pump();
  await tester.pump(kPostRecordingPromptDelay);
  await tester.pumpAndSettle();
  return (notifier: notifier, sent: sent, launched: launched);
}

Future<List<String>> _flushEvents(
  WidgetTester tester,
  List<Map<String, String>> sent,
) async {
  await tester.runAsync(() async {
    // Give the watcher's fire-and-forget telemetry requests time to land.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  return sent.map((b) => '${b['e_c']}/${b['e_a']}/${b['e_n']}').toList();
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  tearDown(() {
    githubInviteIsMacOsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  testWidgets(
    'shows the invitation with the three buttons and no rating text',
    (tester) async {
      final r = await _pump(tester, macOs: true);

      expect(find.text(l10n.githubInviteTitle), findsOneWidget);
      expect(find.text(l10n.githubInviteBody), findsOneWidget);
      expect(find.text(l10n.githubInviteOpen), findsOneWidget);
      expect(find.text(l10n.githubInviteLater), findsOneWidget);
      expect(find.text(l10n.githubInviteNever), findsOneWidget);
      expect(find.byKey(const ValueKey('github-invite-open')), findsOneWidget);
      expect(r.notifier.calls, ['impression']);
      expect(await _flushEvents(tester, r.sent), [
        'review/github_invite_shown/mas',
      ]);
    },
  );

  testWidgets('Mac App Store build reports the mas label, Windows msstore', (
    tester,
  ) async {
    final r = await _pump(tester, macOs: false);
    expect(await _flushEvents(tester, r.sent), [
      'review/github_invite_shown/msstore',
    ]);
  });

  testWidgets(
    '"Auf GitHub ansehen" opens the repository and ends the invitation',
    (tester) async {
      final r = await _pump(tester, macOs: true);
      await tester.tap(find.byKey(const ValueKey('github-invite-open')));
      await tester.pumpAndSettle();

      expect(r.launched, [kGitHubRepoUrl]);
      expect(r.notifier.calls, ['impression', 'starOpened']);
      expect(await _flushEvents(tester, r.sent), [
        'review/github_invite_shown/mas',
        'review/github_invite_clicked/mas',
      ]);
    },
  );

  testWidgets('"Später" records a later-dismissal and opens nothing', (
    tester,
  ) async {
    final r = await _pump(tester, macOs: true);
    await tester.tap(find.byKey(const ValueKey('github-invite-later')));
    await tester.pumpAndSettle();

    expect(r.launched, isEmpty);
    expect(r.notifier.calls, ['impression', 'dismiss:later']);
    expect(await _flushEvents(tester, r.sent), [
      'review/github_invite_shown/mas',
      'review/github_invite_declined/later',
    ]);
  });

  testWidgets('"Nicht mehr fragen" dismisses permanently', (tester) async {
    final r = await _pump(tester, macOs: true);
    await tester.tap(find.byKey(const ValueKey('github-invite-never')));
    await tester.pumpAndSettle();

    expect(r.launched, isEmpty);
    expect(r.notifier.calls, ['impression', 'dismiss:permanent']);
    expect(await _flushEvents(tester, r.sent), [
      'review/github_invite_shown/mas',
      'review/github_invite_declined/never',
    ]);
  });

  testWidgets('Escape counts as "Später", not as a permanent stop', (
    tester,
  ) async {
    final r = await _pump(tester, macOs: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(r.notifier.calls, ['impression', 'dismiss:later']);
    expect(await _flushEvents(tester, r.sent), [
      'review/github_invite_shown/mas',
      'review/github_invite_declined/dismissed',
    ]);
  });

  for (final phase in [
    RecordingPhase.recording,
    RecordingPhase.transcribing,
    RecordingPhase.refining,
  ]) {
    testWidgets('stays silent while the phase is $phase', (tester) async {
      final r = await _pump(tester, macOs: true, phase: phase);

      expect(find.text(l10n.githubInviteTitle), findsNothing);
      expect(r.notifier.calls, ['defer']);
      expect(r.sent, isEmpty);
    });
  }

  testWidgets(
    'a rating claim in the same session blocks the invitation (no overlap)',
    (tester) async {
      final r = await _pump(tester, macOs: true, occupied: true);

      expect(find.text(l10n.githubInviteTitle), findsNothing);
      // Deferred without a displayed impression, so it stays due for a later
      // session instead of counting against the cap.
      expect(r.notifier.calls, ['defer']);
      expect(r.sent, isEmpty);
    },
  );
}
