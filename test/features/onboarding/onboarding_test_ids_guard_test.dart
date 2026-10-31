/// Ticket 15 guard (`internal-notes*`): every
/// interactive element and every heading of the onboarding carries a stable,
/// language-independent `onboarding-<step>-<element>` identifier, and no two
/// nodes share one.
///
/// The walk visits each step in the order `buildOnboardingStepIds` defines
/// and inspects the semantics tree of the page it shows, on macOS, Windows and
/// Linux, because the Access page's content differs per platform.
///
/// Every page is inspected, the hotkey page included (Onboarding v6, V05).
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show hotkeyRegistrationStatusProvider;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/telemetry_service.dart';

import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart';
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;

/// Steps the guard does not inspect yet (see the library comment). None now.
const _deferredSteps = <OnboardingStepId>{};

final _identifierPattern = RegExp(r'^onboarding-[a-z0-9]+(-[a-z0-9]+)*$');

/// Walks [root] and returns the labels of every interactive node or heading
/// that lacks a well-formed identifier, plus every identifier it sees.
///
/// A node that repeats its nearest ancestor's identifier is the same element
/// seen through a wrapper (the wrapper and the widget it wraps both carry the
/// id), so it is counted once.
void _collect(
  SemanticsNode root,
  String where,
  List<String> offenders,
  List<String> identifiers,
) {
  void visit(SemanticsNode node, String ancestorId) {
    final data = node.getSemanticsData();
    final interactive =
        data.hasAction(SemanticsAction.tap) ||
        data.flagsCollection.isButton ||
        data.flagsCollection.isTextField ||
        data.flagsCollection.isToggled.name != 'none' ||
        data.flagsCollection.isSlider ||
        data.flagsCollection.isHeader;
    final id = data.identifier;
    final sameElement = id.isNotEmpty && id == ancestorId;
    if (id.isNotEmpty && !sameElement) identifiers.add(id);
    if (interactive && !_identifierPattern.hasMatch(id)) {
      offenders.add(
        '$where: "${data.label}" (identifier "$id", header '
        '${data.flagsCollection.isHeader}, button '
        '${data.flagsCollection.isButton}, tap '
        '${data.hasAction(SemanticsAction.tap)}, children '
        '${node.childrenCount}, ancestor "$ancestorId")',
      );
    }
    final childAncestorId = id.isEmpty ? ancestorId : id;
    node.visitChildren((child) {
      visit(child, childAncestorId);
      return true;
    });
  }

  visit(root, '');
}

/// The practice step holds "Next" until a dictation succeeds; the walk is not
/// about the practice step, so it counts as done.
class _PracticeDone extends OnboardingTestRecordingSucceededNotifier {
  @override
  bool build() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('every interactive onboarding element has a unique identifier '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final handle = tester.ensureSemantics();

      final client = MockClient((_) async => http.Response('', 204));
      await tester.pumpWidget(
        makeTestable(
          disableAnimations: true,
          const OnboardingOverlay(),
          size: const Size(1280, 1600),
          locale: const Locale('en'),
          overrides: [
            onboardingTestRecordingSucceededProvider.overrideWith(
              _PracticeDone.new,
            ),
            onboardingMicProbeProvider.overrideWithValue(
              OnboardingFakeMicProbe(),
            ),
            audioInputDevicesProvider.overrideWith(
              (ref) async => const ['Default'],
            ),
            settingsProvider.overrideWith(
              () => OnboardingFakeSettings(AppSettings.defaults),
            ),
            micPermissionCheckerProvider.overrideWithValue(
              OnboardingCountingMicChecker(),
            ),
            hotkeyRegistrationStatusProvider.overrideWith(
              OnboardingFakeHotkey.new,
            ),
            recordingOrchestratorProvider.overrideWith(
              OnboardingFakeOrchestrator.new,
            ),
            modelDownloadProvider.overrideWith(OnboardingFakeWhisper.new),
            parakeetDownloadProvider.overrideWith(OnboardingFakeParakeet.new),
            telemetryProvider.overrideWith(
              (ref) => TelemetryService(
                client: client,
                endpointUrl: 'https://stats.example.invalid',
                siteId: 1,
                consentGranted: true,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final offenders = <String>[];
      // Identifiers per page: the shell's own controls (Back, Next, the
      // language picker) show up on every page with the same id, so the
      // uniqueness invariant is per page, not across the whole walk.
      final identifiers = <String>[];
      final duplicates = <String>{};
      final steps = buildOnboardingStepIds();
      for (final step in steps) {
        // Flush the current page's semantics first: the root node is only
        // present after a frame has been painted since the last tap.
        await tester.pump();
        // The semantics owner lives on the render view's pipeline owner, not on
        // the root one, so read it from the view the page is painted into.
        final owner = tester.binding.renderViews.first.owner?.semanticsOwner;
        expect(owner, isNotNull, reason: 'semantics must be enabled');
        final root = owner!.rootSemanticsNode;
        expect(root, isNotNull, reason: 'no semantics tree on ${step.name}');
        if (!_deferredSteps.contains(step)) {
          final pageIds = <String>[];
          _collect(root!, step.name, offenders, pageIds);
          duplicates.addAll(
            pageIds.where((id) => pageIds.where((o) => o == id).length > 1),
          );
          identifiers.addAll(pageIds);
        }
        if (step == OnboardingStepId.privacy) break;
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
      }

      // Restore the override and dispose the handle before the expectations:
      // flutter_test verifies both at the end of the body, before the
      // tear-down callbacks run.
      debugDefaultTargetPlatformOverride = null;
      handle.dispose();
      expect(
        offenders,
        isEmpty,
        reason: 'interactive elements or headings without an identifier',
      );
      expect(
        duplicates,
        isEmpty,
        reason: 'identifiers must be unique on each page',
      );
      expect(
        identifiers,
        isNotEmpty,
        reason: 'the walk must see at least one identifier',
      );
    });
  }
}
