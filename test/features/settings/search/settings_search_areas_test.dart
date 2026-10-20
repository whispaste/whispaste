/// Search jumps land in the right area (WP-23, `07-settings-ia.md` §4):
/// every search row is rendered by the area its entry names, and a jump to
/// that row switches the page there and shows the row.
///
/// Some rows only exist in a given state (an engine choice, a banner, a
/// toggle that is on). Each such state is set up explicitly in [_states] and
/// the test asserts that its rows render there.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/recording/clipping_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/sections/linux_paste_shortcut_row.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/autostart_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';
import 'package:whispaste/services/paste/paster.dart'
    show PasteCapability, PasteCapabilityStatus;
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/review_prompt_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart';
import 'package:whispaste/services/stable_revert_hint_service.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

import '../../../fixtures/test_helpers.dart';
import '../settings_area_fixture.dart';
import '../../../fixtures/record_device_listing_stub.dart';

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

class _DeepLinkScrollTarget extends SettingsScrollTargetNotifier {
  _DeepLinkScrollTarget(this._target);

  final String _target;

  @override
  String? build() => _target;
}

class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _AutostartFailure extends AutostartSyncFailureNotifier {
  @override
  Object? build() => StateError('autostart sync failed (test)');
}

/// A settled, ready capability: the real probe asks the native host, which
/// never answers in a widget test.
class _ReadyPaste extends PasteCapabilityNotifier {
  @override
  PasteCapabilityState build() => const PasteCapabilityState(
    capability: PasteCapability(status: PasteCapabilityStatus.ready),
  );

  @override
  Future<void> check({bool prompt = false}) async {}
}

class _ClippedRecording extends ClippingStateNotifier {
  @override
  ClippingState build() => const ClippingState(count: 3);
}

class _BetaRevertHint extends StableRevertHintNotifier {
  @override
  StableRevertHintState build() =>
      const StableRevertHintState(visible: true, stableVersion: '1.4.0');
}

const _testCudaPack = CudaPackInfo(
  id: 'cuda-test',
  url: 'https://example.invalid/cuda-pack.zip',
  archiveSizeBytes: 1000000,
  archiveSha256: 'test',
  files: [],
);

class _CudaPackOffered extends CudaPackNotifier {
  @override
  CudaPackState build() => const CudaPackState(pack: _testCudaPack);
}

class _TokenIssued extends AutomationApiController {
  @override
  AutomationApiState build() => const AutomationApiState(token: 'test-token');
}

/// Settings with one change applied on top of [AppSettings.defaults].
Override _settingsWith(AppSettings Function(AppSettings s) change) =>
    settingsProvider.overrideWith(
      () => _FixedSettings(change(AppSettings.defaults)),
    );

/// A state in which some search rows exist. [rowIds] are the rows that only
/// render there; [overrides] set that state up.
class _RowState {
  const _RowState({
    required this.name,
    required this.area,
    required this.rowIds,
    required this.overrides,
  });

  final String name;
  final SettingsArea area;
  final Set<String> rowIds;
  final List<Override> Function() overrides;
}

final List<_RowState> _states = [
  _RowState(
    name: 'autostart failed',
    area: SettingsArea.general,
    rowIds: const {'general-autostart-error'},
    overrides: () => [
      autostartSyncFailureProvider.overrideWith(_AutostartFailure.new),
    ],
  ),
  _RowState(
    name: 'rating reminder opted out',
    area: SettingsArea.general,
    rowIds: const {'general-review-prompt-restore'},
    overrides: () => [reviewPromptOptOutProvider.overrideWith((ref) => true)],
  ),
  _RowState(
    name: 'smart-mode hotkey on, translate preset',
    area: SettingsArea.shortcuts,
    rowIds: const {
      'general-hotkey-smart-mode-target',
      'general-hotkey-smart-mode-combination',
    },
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          smartModeHotkey: s.smartModeHotkey.copyWith(
            smartModeHotkeyEnabled: true,
            smartModeHotkeyPreset: 'translate',
          ),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'clipped recording',
    area: SettingsArea.recording,
    rowIds: const {'recording-clipping-hint'},
    overrides: () => [
      clippingStateProvider.overrideWith(_ClippedRecording.new),
    ],
  ),
  _RowState(
    name: 'keep model loaded after idle time',
    area: SettingsArea.speech,
    rowIds: const {'speech-keep-loaded-minutes'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(stt: s.stt.copyWith(idleTimeoutMinutes: 10)),
      ),
    ],
  ),
  _RowState(
    name: 'on-device Parakeet',
    area: SettingsArea.speech,
    rowIds: const {'speech-parakeet'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          stt: s.stt.copyWith(
            provider: SttProviderType.onDevice.value,
            engine: OnDeviceEngine.parakeet.value,
          ),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'on-device Whisper with CUDA pack offered',
    area: SettingsArea.speech,
    rowIds: const {'speech-cuda-pack'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          stt: s.stt.copyWith(
            provider: SttProviderType.onDevice.value,
            engine: OnDeviceEngine.whisper.value,
          ),
        ),
      ),
      cudaPackProvider.overrideWith(_CudaPackOffered.new),
      cudaPackOfferedProvider.overrideWith((ref) => true),
    ],
  ),
  // Store build: the driver download is not allowed, so the row stays with
  // the disabled reason (WP-23g).
  _RowState(
    name: 'CUDA pack in the Store build (disabled, with reason)',
    area: SettingsArea.speech,
    rowIds: const {'speech-cuda-pack'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          stt: s.stt.copyWith(
            provider: SttProviderType.onDevice.value,
            engine: OnDeviceEngine.whisper.value,
          ),
        ),
      ),
      cudaPackProvider.overrideWith(_CudaPackOffered.new),
      cudaPackOfferedProvider.overrideWith((ref) => true),
      deployChannelProvider.overrideWith((ref) => DeployChannel.store),
    ],
  ),
  _RowState(
    name: 'Deepgram cloud speech',
    area: SettingsArea.speech,
    rowIds: const {'speech-deepgram-key'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          stt: s.stt.copyWith(provider: SttProviderType.deepgram.value),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'Linux with Auto-Paste',
    area: SettingsArea.textInsert,
    rowIds: const {'text-linux-always-shift-paste'},
    overrides: () => [
      linuxPasteShortcutRowShownProvider.overrideWith((ref) => true),
      pasteCapabilityNotifierProvider.overrideWith(_ReadyPaste.new),
      linuxFocusStatusProvider.overrideWith(
        (ref) async => LinuxFocusStatus.unsupported,
      ),
      _settingsWith(
        (s) => s.copyWithSections(
          afterTranscriptionSection: const AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'cloud smart mode',
    area: SettingsArea.textInsert,
    rowIds: const {'text-smart-mode-key', 'text-smart-mode-target'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          smartMode: s.smartMode.copyWith(
            provider: SmartModeProviderType.openAI.value,
            standardPreset: 'translate',
          ),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'local smart mode with engine available',
    area: SettingsArea.textInsert,
    rowIds: const {'text-smart-mode-model', 'text-smart-mode-speed'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          smartMode: s.smartMode.copyWith(
            provider: SmartModeProviderType.local.value,
          ),
        ),
      ),
      smartModeLocalEngineAvailableProvider.overrideWith((ref) => true),
    ],
  ),
  _RowState(
    name: 'history hides on open',
    area: SettingsArea.privacy,
    rowIds: const {'privacy-history-pin', 'privacy-history-auto-lock'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          history: s.history.copyWith(historyHideOnOpen: true),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'autosave on',
    area: SettingsArea.privacy,
    rowIds: const {'privacy-backup-status'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          autosave: const SettingsAutosaveSettings(enabled: true),
        ),
      ),
    ],
  ),
  _RowState(
    name: 'automation API on with token',
    area: SettingsArea.advanced,
    rowIds: const {'advanced-automation-status', 'advanced-automation-token'},
    overrides: () => [
      _settingsWith(
        (s) => s.copyWithSections(
          automationApi: s.automationApi.copyWith(enabled: true),
        ),
      ),
      automationApiControllerProvider.overrideWith(_TokenIssued.new),
    ],
  ),
  _RowState(
    name: 'beta channel just switched to stable',
    area: SettingsArea.advanced,
    rowIds: const {'advanced-beta-rollback-hint'},
    overrides: () => [
      stableRevertHintProvider.overrideWith(_BetaRevertHint.new),
    ],
  ),
];

/// The state that makes [rowId] render, or null when the default page shows it.
_RowState? _stateFor(String rowId) {
  for (final state in _states) {
    if (state.rowIds.contains(rowId)) return state;
  }
  return null;
}

/// Entries that open a page of their own (Wörterbuch) instead of a settings
/// area, so they are not rendered inside the settings page.
bool _rendersInSettings(SettingsSearchEntry entry) =>
    entry.area != SettingsRowArea.dictionary &&
    entry.area != SettingsRowArea.help;

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      const SettingsPage(),
      locale: const Locale('en'),
      overrides: [
        hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
        ...overrides,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// Row ids currently built on the page, read from their `settings-row-<id>` keys.
Set<String> _renderedRowIds(WidgetTester tester) => {
  for (final element
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('settings-row-'),
          )
          .evaluate())
    (element.widget.key! as ValueKey<String>).value.substring(
      'settings-row-'.length,
    ),
};

/// The app is desktop-only; flutter_test defaults to Android, which would hide
/// the macOS/Windows-only floating-button section. The override is reset inside
/// the test body, because flutter_test checks foundation invariants before any
/// tearDown runs.
void _desktopTest(String name, WidgetTesterCallback body) =>
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  stubRecordDeviceListing();
  final entries = kSettingsSearchTable.where(_rendersInSettings).toList();

  // Each entry names an area (its host). Every row of that area must render
  // there, so a search jump to it scrolls to a row that exists.
  for (final area in SettingsArea.values) {
    final hosted = entries.where((e) => e.area.hostArea == area);
    final conditional = _states.where((s) => s.area == area);
    final defaultExpected = hosted
        .map((e) => e.rowId)
        .where((id) => _stateFor(id) == null)
        .toSet();
    if (defaultExpected.isNotEmpty) {
      _desktopTest('area ${area.id} renders every default search row', (
        tester,
      ) async {
        await _pump(tester, [settingsAreaAt(area)]);
        final rendered = _renderedRowIds(tester);
        expect(
          rendered.containsAll(defaultExpected),
          isTrue,
          reason:
              'missing in ${area.id}: ${defaultExpected.difference(rendered)}',
        );
      });
    }
    for (final state in conditional) {
      _desktopTest('area ${area.id} renders rows of: ${state.name}', (
        tester,
      ) async {
        await _pump(tester, [settingsAreaAt(area), ...state.overrides()]);
        final rendered = _renderedRowIds(tester);
        expect(
          rendered.containsAll(state.rowIds),
          isTrue,
          reason: 'missing in ${area.id}: ${state.rowIds.difference(rendered)}',
        );
      });
    }
  }

  // Rows that moved to the Help page (Hilfe) are not in Settings: a jump to
  // one leaves Settings for the Help page.
  for (final entry in kSettingsSearchTable.where(
    (e) => e.area == SettingsRowArea.help,
  )) {
    _desktopTest('jump to ${entry.rowId} opens the help page', (tester) async {
      await _pump(tester, [
        settingsScrollTargetProvider.overrideWith(
          () => _DeepLinkScrollTarget(entry.rowId),
        ),
      ]);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      expect(container.read(activePageProvider), 'help', reason: entry.rowId);
    });
  }

  // A deep link or search selection on any row switches to its host area
  // and shows the row. This covers the cross-area jumps.
  for (final entry in entries) {
    _desktopTest('jump to ${entry.rowId} opens ${entry.area.name} area', (
      tester,
    ) async {
      final state = _stateFor(entry.rowId);
      await _pump(tester, [
        settingsScrollTargetProvider.overrideWith(
          () => _DeepLinkScrollTarget(entry.rowId),
        ),
        ...?state?.overrides(),
      ]);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      expect(
        container.read(settingsAreaProvider),
        entry.area.hostArea,
        reason: entry.rowId,
      );
      expect(
        _renderedRowIds(tester),
        contains(entry.rowId),
        reason: entry.rowId,
      );
    });
  }
}
