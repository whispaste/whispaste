/// System tray integration for desktop platforms.
///
/// Provides a tray icon with context menu for quick access to
/// recording, settings, and quitting the app. Uses `tray_manager`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/build_config.dart' show kAutoPasteSupported;
import '../core/config/settings_enums.dart' show OnDeviceEngine, OverlayMode;
import '../core/config/settings_labels.dart'
    show afterTranscriptionStatusLabel, formatHotkeyShortcut, modifierOnlyLabel;
import '../core/config/settings_provider.dart';
import '../core/config/selectable_speech_models.dart';
import '../core/config/stt_choice.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/locale_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/navigation/page_state.dart'
    show settingsLanguageDialogRequestProvider, settingsScrollTargetProvider;
import 'paste/paster.dart' show PasteCapabilityStatus;
import '../core/recording/recording_state.dart';
import '../features/feedback/feedback_type.dart';
import '../widgets/model_ram_precheck_dialog.dart';
import '../core/data/database.dart' show HistoryEntry, historyDatabaseProvider;
import '../core/data/history_providers.dart';
import '../features/history/data/history_lock.dart';
import 'desktop_paste/desktop_paste_controller.dart';
import 'floating_overlay/overlay_hide_rules.dart';
import 'audio_service.dart';
import 'graceful_shutdown.dart';
import 'quit_deadline.dart';
import 'quit_guard.dart';
import 'app_commands/app_command.dart';
import 'app_commands/tray_choice_commands.dart';
import 'app_commands/tray_command_adapter.dart';
import 'tray_recent_copy.dart';
import 'tray_panel/tray_panel_controller.dart';
import 'tray_panel/tray_panel_protocol.dart';
import 'app_commands/tray_command_catalog.dart';
import 'app_profiles/app_profile.dart';
import 'app_profiles/app_profile_choice.dart';
import 'app_profiles/app_profile_repository.dart';
import 'app_profiles/app_profile_resolver.dart';
import 'microphone_selection_service.dart';
import 'support/support_capabilities.dart';
import 'support/support_state.dart';
import 'model_download_service.dart';
import 'paste/paste_policy.dart' show resolveAfterTranscriptionAction;
import 'permissions/tcc_entry_reset_confirm.dart' show l10nForLocaleCode;
import 'stt/stt_bundle.dart' show localSttBundleProvider;
import 'tray_icon_state.dart';
import 'tray_language_menu.dart';
import 'tray_host_probe.dart';
import 'tray_mic_menu.dart';
import 'tray_panel/status_item_name.dart';
import 'tray_submenu_builder.dart' show trayRadioValueFromKey;
import 'window_activation.dart';
import 'user_models/user_model.dart' show UserModel;
import 'user_models/user_models_provider.dart' show userModelsProvider;

// ---------------------------------------------------------------------------
// Action-needed menu-item keys
// ---------------------------------------------------------------------------

/// Default "action needed" tray entry: tapping it takes the user to the
/// after-transcription settings, where the relevant switches live.
const String kTrayPasteActionNeededKey = 'paste_action_needed';

/// The "action needed" entry for a *blocked Auto-Paste permission*, kept
/// separate from [kTrayPasteActionNeededKey] so its tap can run the recovery
/// directly instead of opening settings.
///
/// This is the one paste failure the user cannot resolve by reading a settings
/// page — it needs a TCC grant. The tray is also the only failure surface that
/// persists (a notification expires, the Dock bounce stops), so it is the one
/// most likely to be tapped long after the fact, and therefore the one that
/// must not dead-end.
const String kTrayPastePermissionActionNeededKey =
    'paste_permission_action_needed';

/// What the tray must do when the Auto-Paste permission status changes.
enum TrayPermissionChange { show, clear, none }

/// Maps a permission status transition to the tray action. `show` when the
/// permission newly reads missing, `clear` when it newly reads ready again,
/// `none` otherwise. Pure, so the tray reaction is testable without a tray.
TrayPermissionChange trayPermissionChangeFor(
  PasteCapabilityStatus? previous,
  PasteCapabilityStatus? next,
) {
  if (next == previous) return TrayPermissionChange.none;
  if (next == PasteCapabilityStatus.permissionMissing) {
    return TrayPermissionChange.show;
  }
  if (next == PasteCapabilityStatus.ready) return TrayPermissionChange.clear;
  return TrayPermissionChange.none;
}

/// Label and menu key of the tray entry for a missing Auto-Paste permission.
/// On macOS it runs the grant recovery. Linux has no grant to run: the fix is
/// a one-time udev rule whose command the Auto-Paste settings show, so the
/// entry names the setup and leads there (XP-5-06).
({String label, String key}) trayPermissionEntryFor(
  L10n l10n,
  TargetPlatform platform,
) => platform == TargetPlatform.linux
    ? (
        label: l10n.pasteNotificationLinuxUinputTray,
        key: kTrayPasteActionNeededKey,
      )
    : (
        label: l10n.pasteNotificationPermissionBlockedTray,
        key: kTrayPastePermissionActionNeededKey,
      );

/// Menu key of the Linux-only "Open panel" entry (#920). Not part of the
/// command tree: the macOS menu bar and the button menu never show it.
const kTrayOpenPanelKey = 'open_tray_panel';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages the system tray icon and its context menu.
///
/// Listens to [recordingProvider] to update the tray tooltip and menu
/// label between "Start Recording" and "Stop Recording".
class TrayService extends Notifier<void> implements TrayListener {
  static final _log = AppLogger('TrayService');

  /// Callback invoked when the user clicks "Start/Stop Recording" in the tray.
  VoidCallback? onToggleRecording;

  /// Callback invoked when the user clicks a navigation item (e.g. 'settings').
  ValueChanged<String>? onNavigate;

  /// Opens the history page's file picker for "Transcribe file…".
  VoidCallback? onTranscribeFile;

  /// Opens the clipboard quick-paste side panel. Its window only, the main
  /// window stays where it is (UIA-SHL-09).
  VoidCallback? onOpenSidePanel;

  /// Copies the recent recording [recordingId] (from a `recent-` menu id) and
  /// completes when it is on the clipboard; throws when the copy failed. The
  /// floating button uses it to flash its copy feedback.
  Future<void> copyRecentRecording(String recordingId) =>
      _recentCopier.copy(recordingId);

  /// Whether the side panel is enabled. The menu entry appears only then,
  /// because the panel controller exists only while it is enabled.
  bool _sidePanelAvailable = false;

  /// Shows or hides the side panel entry and rebuilds the menu on change.
  void setSidePanelAvailable(bool available) {
    if (available == _sidePanelAvailable) return;
    _sidePanelAvailable = available;
    // Before init the menu does not exist yet; init builds it with this flag.
    if (!_isDesktop || !_initialized) return;
    // Runs from build() via the bootstrap; a microtask keeps the provider
    // write out of the build frame.
    _scheduleRebuild();
  }

  @override
  void build() {
    // Only run on desktop platforms.
    if (!_isDesktop) return;

    // Labels follow the app language from the start (later changes come in
    // through [updateLocalizations]). Before this, they were only set with the
    // first recording state, so the menu stayed English until then.
    _l10n = l10nForLocaleCode(ref.read(localeProvider).languageCode);

    // Surfaces that render the tray tree (the floating button, #393) ask
    // through the snapshot provider for a fresh microphone list.
    ref.read(trayMenuSnapshotProvider.notifier).onRefresh = _refreshMicDevices;
    _initDone = Future.microtask(_init);
    // The choice groups show the settings and downloads the dock writes too,
    // so they are re-read whenever one of those changes.
    ref.listen(
      settingsProvider.select((async) => _trayMenuSettings(async.value)),
      (_, _) => _scheduleRebuild(),
    );
    ref.listen(modelDownloadProvider, (_, _) => _scheduleRebuild());
    // Recent recordings and the PIN lock both change the submenu. A lock that
    // engages also drops the copy texts at once.
    ref.listen(
      historyHeadProvider(trayRecentLimit),
      (_, _) => _scheduleRebuild(),
    );
    ref.listen(historyContentHiddenProvider, (_, hidden) {
      if (hidden) _recentCopier.clear();
      _scheduleRebuild();
    });
    ref.listen(localSttBundleProvider, (_, _) => _scheduleRebuild());
    // The coffee entry of a store build waits for the store's answer.
    ref.listen(supportStoreTipAvailableProvider, (_, _) => _scheduleRebuild());
    ref.listen(profileChoiceProvider, (_, _) => _scheduleRebuild());
    // The hide hour of the overlay (overlay F) adds and removes its entry.
    ref.listen(overlayHiddenUntilProvider, (_, _) => _scheduleRebuild());
    ref.listen(appProfilesProvider, (prev, next) {
      if (_profileMenuKey(prev?.value) != _profileMenuKey(next.value)) {
        _scheduleRebuild();
      }
    });
    ref.onDispose(() {
      unawaited(_panelSub?.cancel());
    });
    ref.onDispose(_destroy);
  }

  // ── TrayListener callbacks ────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    // Left click opens the panel where a panel shell exists (macOS, #920);
    // elsewhere it still restores the window.
    unawaited(_onPrimaryClick());
  }

  @override
  void onTrayIconRightMouseDown() {
    _showContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    activateCommand(key);
  }

  /// Runs the action of the command [key] (its id in the command tree). The
  /// tray menu and the macOS menu bar both call this, so one id does the same
  /// thing on every surface.
  void activateCommand(String key) {
    switch (key) {
      case 'show':
        _showWindow();
      case 'toggle_recording':
        onToggleRecording?.call();
      case 'transcribe_file':
        _showWindow();
        onTranscribeFile?.call();
      case 'settings':
        _showWindow();
        onNavigate?.call('settings');
      case 'feedback':
        // Opens the plain form (no type preset); the menu bar's Idea entry
        // presets the type itself.
        ref.read(feedbackPresetTypeProvider.notifier).set(null);
        _showWindow();
        onNavigate?.call('feedback');
      case 'side_panel':
        onOpenSidePanel?.call();
      case 'quit':
        _requestQuit();
      case kTrayOpenPanelKey:
        unawaited(_onPrimaryClick());
      case langMoreMenuKey:
        // "More languages…" opens the full selection: Settings at the
        // language row, with the language dialog on top (#1209).
        ref.read(settingsScrollTargetProvider.notifier).set('speech-language');
        ref.read(settingsLanguageDialogRequestProvider.notifier).request();
        _showWindow();
        onNavigate?.call('settings');
      case TrayCommandIds.resumeOnboarding:
        // The window reopens on the page the paused setup stopped at: the
        // overlay resumes from the saved position, as after a restart.
        _showWindow();
      case TrayCommandIds.unlockHistory || trayOpenHistoryId:
        _showWindow();
        onNavigate?.call('history');
      case TrayCommandIds.coffee:
        _openCoffee();
      case TrayCommandIds.overlayShowAgain:
        ref.read(overlayHiddenUntilProvider.notifier).showAgain();
      case TrayCommandIds.overlayTurnOn:
        unawaited(
          ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWith(
                  overlayMode: OverlayMode.floating.value,
                  showOverlay: true,
                ),
              ),
        );
      default:
        final recentId = trayRecentIdFromKey(key);
        if (recentId != null) {
          _copyRecent(recentId);
          return;
        }
        final micLabel = micLabelFromMenuKey(key);
        if (micLabel != null) {
          _selectMicrophone(micLabel);
          return;
        }
        final langCode = langCodeFromMenuKey(key);
        if (langCode != null) {
          _selectLanguage(langCode);
          return;
        }
        final speechValue = trayRadioValueFromKey(kTraySpeechModelPrefix, key);
        if (speechValue != null) {
          _selectSpeechModel(speechValue);
          return;
        }
        final preset = trayRadioValueFromKey(kTraySmartModePrefix, key);
        if (preset != null) {
          _selectSmartMode(preset);
          return;
        }
        final output = trayRadioValueFromKey(kTrayOutputPrefix, key);
        if (output != null) {
          _selectOutputAction(output);
          return;
        }
        final profileChoice = _profileChoiceForKey(key);
        if (profileChoice != null) {
          _selectProfile(profileChoice);
          return;
        }
        // Action-needed item or any custom key.
        openActionNeeded(key);
    }
  }

  /// The coffee entry opens the support tab in every build. That tab shows
  /// Ko-fi and Buy Me a Coffee with equal rank, and the store purchase where
  /// the store sells it, so the tray never prefers one provider.
  void _openCoffee() {
    _showWindow();
    onNavigate?.call('support');
  }

  /// Opens the window and routes [key] to the action handler for resolution,
  /// as a click on the action-needed tray item does. Notifications whose fix
  /// lives in the app reuse it so both surfaces lead to the same place.
  void openActionNeeded(String key) {
    _showWindow();
    onActionNeededTap?.call(key);
  }

  /// Click handler for the action-needed item in the tray menu — fired
  /// when the user clicks "⚠ Auto-Paste blocked" (or similar).
  ValueChanged<String>? onActionNeededTap;

  @override
  void onTrayIconMouseUp() {}
  @override
  void onTrayIconRightMouseUp() {}

  // ── Public API ────────────────────────────────────────────────────────────

  /// Updates the tray menu to reflect the current recording state.
  void updateRecordingState(RecordingState recording, {L10n? l10n}) {
    if (!_isDesktop || !_initialized) return;
    // Keep the labels already set when the caller passes none, so the menu
    // does not fall back to another language (UIA-SHL-16).
    if (l10n != null) _l10n = l10n;
    _lastRecording = recording;
    _applyIconState(trayIconStateFor(recording.phase));
    _rebuildMenu();
    _pushPanelContent();
  }

  // ── Tray panel (#920) ─────────────────────────────────────────────────────

  StreamSubscription<TrayPanelEvent>? _panelSub;
  String? _sentPanel;

  /// The panel the user sees; a reported action is checked against it.
  TrayPanelContent? _shownPanel;

  /// Latest menu tree and labels from [_rebuildMenu]; the panel derives its
  /// entries from them, so menu and panel never disagree.
  List<AppCommand> _menuCommands = const [];
  Map<String, String> _menuLabels = const {};

  /// Left click: toggles the panel. A missing shell keeps the previous
  /// behaviour (restore the window); a shell that fails to show falls back to
  /// the native menu, so a click is never dead.
  Future<void> _onPrimaryClick() async {
    final panel = ref.read(trayPanelControllerProvider);
    final content = _panelContent();
    if (panel == null || content == null) {
      await _showWindow();
      return;
    }
    _panelSub ??= panel.events.listen(_onPanelEvent);
    var shown = false;
    try {
      shown = await panel.toggle(content);
    } on Exception catch (e) {
      _log.warning('Tray panel failed, using the menu: $e');
    }
    if (shown) {
      _sentPanel = jsonEncode(content.toMap());
      _shownPanel = content;
    } else {
      await _showContextMenu();
    }
  }

  void _onPanelEvent(TrayPanelEvent event) {
    if (event is! TrayPanelActionEvent) return;
    final shown = _shownPanel;
    if (shown == null) return;
    // Checked against the phase of now: a dictation that started meanwhile
    // locks the microphone and the primary button the same way.
    final current = _panelContent() ?? shown;
    final command = trayCommandForPanelAction(event.action, shown) == null
        ? null
        : trayCommandForPanelAction(event.action, current);
    if (command != null) activateCommand(command);
  }

  TrayPanelContent? _panelContent() {
    final l = _l10n;
    if (l == null) return null;
    final phase = trayPanelPhaseOf(_lastRecording.phase);
    final settings = ref.read(settingsProvider).value;
    return buildTrayPanelContent(
      commands: _menuCommands,
      labels: _menuLabels,
      phase: phase,
      statusLabel: switch (phase) {
        TrayPanelPhase.ready => l.trayStatusReady,
        TrayPanelPhase.recording => l.trayStatusRecording,
        TrayPanelPhase.transcribing => l.statusTranscribing,
      },
      primaryLabel: phase == TrayPanelPhase.recording
          ? l.trayStopRecording
          : l.dockDictate,
      shortcut: settings == null ? '' : trayToggleShortcut(settings, l),
    );
  }

  /// Keeps an open panel in step with the recording state. Only a change is
  /// sent, and a closed panel ignores it natively.
  void _pushPanelContent() {
    final panel = _panelSub == null
        ? null
        : ref.read(trayPanelControllerProvider);
    final content = _panelContent();
    if (panel == null || content == null) return;
    final encoded = jsonEncode(content.toMap());
    if (encoded == _sentPanel) return;
    _sentPanel = encoded;
    _shownPanel = content;
    unawaited(panel.update(content));
  }

  /// Re-labels the tray menu in [l10n]. Called on every app language change;
  /// before the tray is initialized it only stores the labels, and the first
  /// menu build in [_init] uses them.
  void updateLocalizations(L10n l10n) {
    _l10n = l10n;
    if (!_isDesktop || !_initialized) return;
    _rebuildMenu();
  }

  /// Marks an action item visible in the tray menu — top-of-list entry
  /// that survives until [clearActionNeeded]. Use for issues the user
  /// must fix manually (Auto-Paste permission missing, etc.) so the
  /// reminder stays visible when the main window is closed.
  void setActionNeeded({
    required String label,
    required String tooltip,
    String? menuItemKey,
  }) {
    if (!_isDesktop || !_initialized) return;
    _actionNeeded = _ActionNeeded(
      label: label,
      tooltip: tooltip,
      menuItemKey: menuItemKey ?? 'action_needed',
    );
    unawaited(_setToolTip(tooltip));
    _rebuildMenu();
  }

  /// Clears any pending action item from the tray menu. Called when the
  /// user has resolved the issue (e.g. paste succeeded after one failed).
  /// With [ifKey], only an entry with that menu key is cleared, so a
  /// permission reset never removes an unrelated paste-failure entry.
  void clearActionNeeded({String? ifKey}) {
    if (!_isDesktop || !_initialized) return;
    if (_actionNeeded == null) return;
    if (ifKey != null && _actionNeeded!.menuItemKey != ifKey) return;
    _actionNeeded = null;
    unawaited(_setToolTip('WhisPaste'));
    _rebuildMenu();
  }

  /// Whether the tray icon was successfully initialized.
  bool get isInitialized => _initialized;

  /// Completes once the asynchronous tray setup scheduled by [build] has
  /// finished (successfully or not). Tests await this instead of draining
  /// the event queue a fixed number of turns: setup does real asset and file
  /// I/O, and on a loaded machine that outlasted `pumpEventQueue()`.
  @visibleForTesting
  Future<void> get initDone => _initDone;

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _initDone = Future<void>.value();
  bool _initialized = false;
  L10n? _l10n;
  RecordingState _lastRecording = const RecordingState();
  _ActionNeeded? _actionNeeded;
  List<String> _micDeviceLabels = const [micDefaultLabel];

  /// The menu and tooltip last handed to the platform. Recording state
  /// changes many times a second (level, elapsed time) while the menu stays
  /// the same, and tray_manager's Linux plugin builds a new GtkMenu for every
  /// setContextMenu without freeing the old one (GH #159). Only a change is
  /// sent.
  String? _sentMenu;
  String? _sentToolTip;

  /// The idle icon path [_init] handed to the platform; the state variants
  /// fall back to it when their file cannot be found.
  String? _idleIconPath;

  /// The icon state last requested and the path last handed to the
  /// platform (#137). Icon changes run one after another on [_iconChain],
  /// so a quick recording → processing → idle sequence ends on idle.
  TrayIconState _iconState = TrayIconState.idle;
  String? _sentIconPath;
  Future<void> _iconChain = Future<void>.value();

  /// Shows the icon variant for [state] in the tray. Only a change is sent;
  /// a failure keeps the previous icon and never throws (the menu status
  /// line still names the state).
  void _applyIconState(TrayIconState state) {
    if (state == _iconState) return;
    _iconState = state;
    _iconChain = _iconChain.then((_) async {
      if (state != _iconState) return;
      try {
        final path = await _stateIconPath(state);
        if (path == null || path == _sentIconPath) return;
        await trayManager.setIcon(path);
        _sentIconPath = path;
      } on Exception catch (e) {
        _log.warning('Tray state icon update failed (non-fatal): $e');
      }
    });
  }

  /// The path tray_manager needs for [state]: on macOS the asset key (it
  /// loads it from the bundle), elsewhere a file path. Windows and Linux
  /// read the variant from flutter_assets next to the executable; Linux
  /// extracts it from the bundle when that layout is missing, Windows falls
  /// back to the idle icon.
  Future<String?> _stateIconPath(TrayIconState state) async {
    final asset = trayStateIconAsset(state, windows: Platform.isWindows);
    if (asset == null) return _idleIconPath;
    if (defaultTargetPlatform == TargetPlatform.macOS) return asset;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = p.joinAll([
      exeDir,
      'data',
      'flutter_assets',
      ...asset.split('/'),
    ]);
    if (File(bundled).existsSync()) return bundled;
    if (Platform.isLinux) {
      try {
        final bytes = await rootBundle.load(asset);
        final tmp = File(
          p.join(Directory.systemTemp.path, 'whispaste_${p.basename(asset)}'),
        );
        await tmp.writeAsBytes(bytes.buffer.asUint8List());
        return tmp.path;
      } on Exception catch (e) {
        _log.warning('rootBundle tray state icon extraction failed: $e');
      }
    }
    return _idleIconPath;
  }

  Future<void> _setContextMenu(Menu menu) async {
    final content = jsonEncode(trayMenuContent(menu));
    if (content == _sentMenu) return;
    await trayManager.setContextMenu(menu);
    _sentMenu = content;
  }

  /// Never throws: the tooltip is cosmetic, and some callers do not await it
  /// (core review L-16, F16-1). A refused tooltip counts as sent, so a
  /// platform without one (tray_manager on Linux) is asked once per change,
  /// not on every menu rebuild during a recording.
  Future<void> _setToolTip(String toolTip) async {
    if (toolTip == _sentToolTip) return;
    _sentToolTip = toolTip;
    try {
      await trayManager.setToolTip(toolTip);
    } on Exception catch (e) {
      _log.debug('Tray tooltip unavailable: $e');
    }
  }

  Future<void> _init() async {
    try {
      // tray_manager's contract differs per platform: on macOS it loads the
      // icon via `rootBundle.load(iconPath)`, i.e. it wants an asset key;
      // elsewhere it reads a file path. An absolute bundle path only worked
      // on macOS while it needed no URI-encoding — a space in the bundle
      // path ("WhisPaste 2.app") made the load throw and left the tray
      // uninitialized (Sentry FLUTTER_WHISPASTE-DT).
      final iconPath = defaultTargetPlatform == TargetPlatform.macOS
          ? 'assets/icons/logo-dark.png'
          : await _resolveIconPath();
      if (iconPath == null) {
        _log.warning('Tray icon not found — skipping tray setup');
        return;
      }

      await trayManager.setIcon(iconPath);
      _idleIconPath = iconPath;
      _sentIconPath = iconPath;
      // tray_manager's Linux plugin only implements destroy/setIcon/
      // setTitle/setContextMenu — setToolTip throws MissingPluginException
      // there. _setToolTip contains that, so it never aborts the listener and
      // menu setup below (that left the tray icon visible but inert on Linux —
      // no click, no right-click, no menu).
      await _setToolTip('WhisPaste');
      // The icon's accessible name on macOS (#1926); the tooltip keeps the
      // state.
      await nameMacStatusItem();
      trayManager.addListener(this);

      _initialized = true;
      _rebuildMenu();
      _log.info('System tray initialized');
      // Decision via the platform seam (#198); the probe itself is injected.
      if (defaultTargetPlatform == TargetPlatform.linux) {
        final available = await ref.read(trayHostProbeProvider)();
        ref.read(trayHostMissingProvider.notifier).update(missing: !available);
        if (!available) {
          _log.warning(
            'No tray host on the session bus (AppIndicator missing)',
          );
        }
      }
    } on Exception catch (e) {
      _log.warning('Failed to init system tray: $e');
    }
  }

  /// Refreshes the mic device list just-in-time, then pops up the menu.
  ///
  /// The device set changes while the app runs (docking/undocking) and
  /// right-mouse-down is the only pre-popup hook, so a cached list from
  /// startup would go stale.
  Future<void> _showContextMenu() async {
    await _refreshMicDevices();
    try {
      await trayManager.popUpContextMenu();
    } on Exception catch (e) {
      _log.warning('Tray context menu popup failed: $e');
    }
  }

  Future<void> _refreshMicDevices() async {
    try {
      ref.invalidate(audioInputDevicesProvider);
      // Timeout keeps the menu responsive if enumeration hangs on a flaky
      // HAL — the previous list is shown instead.
      _micDeviceLabels = await ref
          .read(audioInputDevicesProvider.future)
          .timeout(const Duration(milliseconds: 800));
    } on Exception catch (e) {
      _log.warning('Mic enumeration for tray menu failed: $e');
    }
    await _rebuildMenu();
  }

  /// Applies a microphone choice made in the tray menu — delegates to the
  /// shared [MicrophoneSelectionService] so tray and status-bar chip behave
  /// identically.
  Future<void> _selectMicrophone(String label) async {
    await ref.read(microphoneSelectionServiceProvider).select(label);
    await _rebuildMenu();
  }

  /// Persists a recognition language picked in the tray's Language submenu.
  /// Like the dock, it applies from the next recording.
  Future<void> _selectLanguage(String code) async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(sttLanguage: code));
    await _rebuildMenu();
  }

  /// The settings the tray menu shows. Other settings (the UI language, for
  /// one) do not rebuild the menu.
  static String _trayMenuSettings(AppSettings? settings) {
    if (settings == null) return '';
    return [
      sttChoiceValue(settings),
      settings.sttLanguageCode,
      settings.stt.favoriteLanguages.join(','),
      settings.smartMode.standardPreset,
      settings.afterTranscriptionAction.name,
      settings.audioInput.microphone,
      settings.sttProviderType.name,
      // The resume entry appears and leaves with the first-run state.
      settings.onboarding.onboardingCompleted,
      // The way back to the overlay appears while it is off (overlay F).
      settings.effectiveOverlayMode.name,
    ].join('|');
  }

  /// Applies a speech-model choice made in the tray, as the dock does. Refused
  /// while a dictation runs, like the greyed-out tray entries.
  Future<void> _selectSpeechModel(String value) async {
    if (isDictationBusy(_lastRecording.phase)) return;
    final current = ref.read(settingsProvider).value;
    if (current != null &&
        !await confirmSttSettingsRamFromApp(
          settings: applySttChoice(current, value),
        )) {
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => applySttChoice(s, value));
    await _rebuildMenu();
  }

  /// Sets the standard Smart Mode preset, as the dock's dropdown does.
  Future<void> _selectSmartMode(String preset) async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            smartMode: s.smartMode.copyWith(standardPreset: preset),
          ),
        );
    await _rebuildMenu();
  }

  /// Sets the after-transcription action, as the dock's output selector does.
  Future<void> _selectOutputAction(String value) async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(afterTranscription: value));
    await _rebuildMenu();
  }

  /// The manual profile choice a tray key stands for, or null for other keys.
  ProfileChoice? _profileChoiceForKey(String key) {
    if (key == kTrayProfileAutomaticId) return const ProfileChoiceAutomatic();
    if (key == kTrayProfileNoneId) return const ProfileChoiceNone();
    final id = trayRadioValueFromKey(kTrayProfilePrefix, key);
    return id == null ? null : ProfileChoiceProfile(id);
  }

  /// Makes [choice] the active profile for the next recordings. A repeated
  /// pick changes nothing and announces nothing.
  void _selectProfile(ProfileChoice choice) {
    final changed = ref.read(profileChoiceProvider.notifier).select(choice);
    if (!changed) return;
    final name = switch (choice) {
      ProfileChoiceProfile(:final profileId) => _profileName(profileId),
      _ => null,
    };
    ref
        .read(profileSwitchFeedbackProvider.notifier)
        .announce(choice: choice, profileName: name);
    unawaited(_rebuildMenu());
  }

  /// What the Profil submenu shows. Rebuilding only when this changes keeps a
  /// first load of an empty list from touching the menu.
  String _profileMenuKey(List<AppProfile>? profiles) => [
    for (final profile in profiles ?? const <AppProfile>[])
      '${profile.id}\u0000${profile.name}',
  ].join('\n');

  String? _profileName(String profileId) {
    final profiles =
        ref.read(appProfilesProvider).value ?? const <AppProfile>[];
    for (final profile in profiles) {
      if (profile.id == profileId) return profile.name;
    }
    return null;
  }

  /// Full text of the recordings the last menu build listed, by id.
  late final TrayRecentCopier _recentCopier = TrayRecentCopier(
    isHidden: () => ref.read(historyContentHiddenProvider),
    readFull: (id) async =>
        (await ref.read(historyDatabaseProvider).entryContents([id]))[id],
    write: (text) => writeTrayCopyTransient(
      text,
      excludedWrite: ref
          .read(desktopPasteControllerProvider)
          ?.writeClipboardTextExcludingHistory,
    ),
  );

  /// Copies a recent recording (see [TrayRecentCopier]).
  void _copyRecent(String id) {
    unawaited(
      _recentCopier
          .copy(id)
          .catchError(
            (Object e, StackTrace st) =>
                _log.error('Copy from tray failed', e, st),
          ),
    );
  }

  /// Menu label of a recent recording: time and a text preview, or time and
  /// word count when [textPreview] is off (history PIN set).
  String _recentLabel(
    HistoryEntry entry,
    L10n l10n, {
    required bool textPreview,
  }) {
    final time = DateFormat.Hm(
      l10n.localeName,
    ).format(entry.timestamp.toLocal());
    if (textPreview) return '$time \u00b7 ${trayRecentLabel(entry.content)}';
    final words = entry.content
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return l10n.trayRecentMeta(time, words);
  }

  /// Rebuilds the menu after the current provider notification has finished.
  /// A listener runs while the provider that changed is still updating, and
  /// the rebuild reads speech models that depend on that same provider.
  void _scheduleRebuild() => unawaited(Future<void>.microtask(_rebuildMenu));

  Future<void> _rebuildMenu() async {
    final l = _l10n;
    // Labels are set in build() before the first menu, so this only guards
    // against a rebuild that runs before the tray has a language at all.
    // The rebuild is scheduled as a microtask: when the provider is disposed
    // in between (app shutdown, a test's container), there is no menu left.
    if (l == null || !ref.mounted) return;
    final settings = ref.read(settingsProvider).value;
    final action = _actionNeeded;
    final labels = trayLabelsFor(l);
    final choices = settings == null
        ? null
        : speechChoicesFor(
            l,
            models: ref.read(selectableSpeechModelsProvider),
            missing: ref.read(missingSelectedSpeechModelProvider),
            own: ref.read(userModelsProvider).models,
          );
    // Locked history never reaches the menu: no items, only the unlock entry.
    final historyLocked = ref.read(historyContentHiddenProvider);
    final recent = historyLocked
        ? const <HistoryEntry>[]
        : ref.read(historyHeadProvider(trayRecentLimit)).value ??
              const <HistoryEntry>[];
    _recentCopier.replace({for (final e in recent) e.id: e.content});
    final textPreview = trayTextPreviewEnabled(
      historyPin: settings?.history.historyPin ?? '',
    );
    final commands = trayCommandTree(
      l,
      historyLocked: historyLocked,
      recentRecordings: [
        for (final e in recent)
          (id: e.id, label: _recentLabel(e, l, textPreview: textPreview)),
      ],
      recording: _lastRecording,
      micDeviceLabels: _micDeviceLabels,
      settings: settings,
      choices: choices,
      profiles: ref.read(appProfilesProvider).value ?? const [],
      profileChoice: ref.read(profileChoiceProvider),
      actionNeeded: action == null
          ? null
          : (id: action.menuItemKey, label: action.label),
      sidePanelAvailable: _sidePanelAvailable,
      coffeeAvailable:
          ref.read(coffeeSupportTargetProvider) != CoffeeSupportTarget.hidden,
      resumeOnboardingAvailable:
          settings != null && !settings.onboarding.onboardingCompleted,
      overlayRestore: trayOverlayRestore(
        l,
        overlayOn: settings?.effectiveOverlayMode != OverlayMode.off,
        hiddenUntil: ref.read(overlayHiddenUntilProvider),
        now: ref.read(overlayHideClockProvider)(),
      ),
    );
    ref.read(trayMenuSnapshotProvider.notifier).publish((
      commands: commands,
      labels: labels,
    ));
    _menuCommands = commands;
    _menuLabels = labels;
    _pushPanelContent();
    try {
      await _setContextMenu(
        Menu(
          items: [
            // Linux: the AppIndicator host reports no icon click, so the panel
            // opens from the first menu entry instead (ADR 0038, decision 5b).
            if (Platform.isLinux &&
                ref.read(trayPanelControllerProvider) != null) ...[
              MenuItem(key: kTrayOpenPanelKey, label: l.trayOpenPanel),
              MenuItem.separator(),
            ],
            ...trayMenuItems(
              commands,
              labelOf: (key) => labels[key] ?? key,
              isMacOS: Platform.isMacOS,
              isWindows: Platform.isWindows,
            ),
          ],
        ),
      );
    } on Exception catch (e) {
      // Same as the tooltip above: a platform without a tray menu must not
      // abort the rest of the update.
      _log.warning('Tray menu update failed (non-fatal): $e');
    }
    if (settings != null && action == null) {
      await _updateTooltip(l, settings, choices!);
    }
  }

  /// The tooltip names the state a tray user needs to know without opening
  /// the menu. An action-needed message owns the tooltip while it is shown.
  Future<void> _updateTooltip(
    L10n l,
    AppSettings settings,
    List<SttChoice> choices,
  ) async {
    final current = sttChoiceValue(settings);
    final speech =
        choices
            .where((c) => c.value == current && !c.needsDownload)
            .map((c) => c.label)
            .firstOrNull ??
        current;
    final preset = settings.smartMode.standardPreset;
    final labels = trayLabelsFor(l);
    final presetName = labels[smartModePresetLabelKey(preset)] ?? preset;
    final output = afterTranscriptionStatusLabel(
      resolveAfterTranscriptionAction(settings.afterTranscriptionAction),
      l,
    );
    // While a dictation runs, its state leads the tooltip (#137).
    final state = trayIconStateFor(_lastRecording.phase);
    // Linux tray_manager has no tooltip; the menu still shows the state.
    await _setToolTip(
      trayStateTooltip(
        state,
        status: labels[trayStatusLabelKey(state)] ?? '',
        details: trayTooltipText(
          speechModel: speech,
          smartMode: l.trayTooltipSmartMode(presetName),
          output: output,
        ),
      ),
    );
  }

  Future<String?> _resolveIconPath() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // On Windows, prefer a dedicated ICO. PNG tray icons often render as an
    // empty transparent slot with `tray_manager`.
    if (Platform.isWindows) {
      final candidates = [
        '$exeDir\\resources\\tray.ico',
        '$exeDir\\tray.ico',
        '$exeDir\\resources\\app_icon.ico',
        '$exeDir\\app_icon.ico',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          _log.info('Resolved tray icon: $path');
          return path;
        }
      }
      _log.warning('No tray icon file found, falling back to executable icon');
      return Platform.resolvedExecutable;
    }

    // macOS / Linux: try known bundle paths first (fast, no I/O allocation).
    if (Platform.isMacOS || Platform.isLinux) {
      final candidates = [
        // macOS .app bundle: flutter_assets inside App.framework (primary)
        p.normalize(
          '$exeDir/../Frameworks/App.framework/Resources/flutter_assets/assets/icons/logo-dark.png',
        ),
        // macOS .app bundle: flutter_assets directly in Resources (fallback)
        p.normalize(
          '$exeDir/../Resources/flutter_assets/assets/icons/logo-dark.png',
        ),
        // macOS .app bundle: Resources root (set via Xcode bundle-resource copy)
        p.normalize('$exeDir/../Resources/tray.png'),
        // Linux: flutter_assets next to executable
        p.normalize('$exeDir/data/flutter_assets/assets/icons/logo-dark.png'),
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          _log.info('Resolved tray icon: $candidate');
          return candidate;
        }
      }

      // Last resort: extract from rootBundle to a temp file.
      // This is reliable regardless of bundle layout changes across Flutter versions.
      try {
        final bytes = await rootBundle.load('assets/icons/logo-dark.png');
        final tmp = File(
          p.join(Directory.systemTemp.path, 'whispaste_tray_icon.png'),
        );
        await tmp.writeAsBytes(bytes.buffer.asUint8List());
        _log.info('Extracted tray icon via rootBundle → ${tmp.path}');
        return tmp.path;
      } on Exception catch (e) {
        _log.warning('rootBundle icon extraction failed: $e');
      }
    }

    return null;
  }

  /// Shows/restores the main window through the shared helper — the identical
  /// sequence (macOS Dock presence, show, focus) this method used to inline,
  /// now also used by the quick-note path (see `window_activation.dart`).
  Future<void> _showWindow() => ref.read(windowActivatorProvider)();

  /// Tray "Beenden". While a dictation runs, the shared quit guard asks first
  /// (UIA-SHL-15, `quit_guard.dart`).
  void _requestQuit() {
    unawaited(() async {
      if (await ref.read(quitGuardProvider).allowQuit()) await _quit();
    }());
  }

  /// Shares [appQuit] with the window quit paths: a tray quit while a window
  /// quit runs (or the other way round) joins it, never a second shutdown.
  Future<void> _quit() => appQuit.run(
    orderlyShutdown: _orderlyQuit,
    hardExit: endProcessWithoutDestructors,
  );

  Future<void> _orderlyQuit() async {
    // Stop the on-device STT engine and WAIT for native teardown (plus DB
    // close) before destroying tray/window — same shared helper as
    // app.dart's onWindowClose and the macOS native-terminate path (see
    // graceful_shutdown.dart). Previously this fired STT stop() without
    // awaiting it and proceeded straight to tray/window destroy, racing
    // native engine teardown against process exit — the same bug class as
    // FLUTTER_WHISPASTE-BC (fixed for onWindowClose/Cmd+Q, but not here):
    // if the process starts tearing down native GPU/ORT resources before
    // the engine actually freed them, ggml's Metal-residency-set teardown
    // assert (or an analogous native check) aborts the whole app.
    await runGracefulEngineShutdown(ref.container);

    try {
      await trayManager.destroy().timeout(const Duration(seconds: 1));
    } on Exception catch (e) {
      _log.debug('Tray destroy failed during quit (non-fatal): $e');
    }

    await windowManager.destroy();
  }

  Future<void> _destroy() async {
    if (!_initialized) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _log.info('System tray destroyed');
    } on Exception catch (e) {
      _log.warning('Tray destroy error: $e');
    }
  }

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

class _ActionNeeded {
  const _ActionNeeded({
    required this.label,
    required this.tooltip,
    required this.menuItemKey,
  });
  final String label;
  final String tooltip;
  final String menuItemKey;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// System tray provider — eagerly watched in the app shell.
/// A built tray menu: its command tree and the labels its keys resolve to.
typedef TrayMenuSnapshot = ({
  List<AppCommand> commands,
  Map<String, String> labels,
});

/// The tray menu as last built, for surfaces that render the same tree: the
/// floating button's context menu shows it (#393), so both menus have the
/// same groups, names and current choices, and every entry runs through
/// [TrayService.activateCommand].
class TrayMenuSnapshotNotifier extends Notifier<TrayMenuSnapshot?> {
  @override
  TrayMenuSnapshot? build() => null;

  /// Set by the tray: re-reads the microphones and rebuilds the menu.
  Future<void> Function()? onRefresh;

  void publish(TrayMenuSnapshot snapshot) => state = snapshot;

  /// Re-reads the microphone list and rebuilds the tree, as a right-click on
  /// the tray icon does. A no-op before the tray service exists.
  Future<void> refresh() => onRefresh?.call() ?? Future<void>.value();
}

final trayMenuSnapshotProvider =
    NotifierProvider<TrayMenuSnapshotNotifier, TrayMenuSnapshot?>(
      TrayMenuSnapshotNotifier.new,
    );

final trayServiceProvider = NotifierProvider<TrayService, void>(
  TrayService.new,
);

/// The Speech-model choices for the tray and the menu bar: the dock's list,
/// built from the same models and missing-model state (UIA-DOCK-02, UIA-MDL-GATE b).
List<SttChoice> speechChoicesFor(
  L10n l, {
  required List<SelectableSpeechModel> models,
  required SelectableSpeechModel? missing,
  List<UserModel> own = const [],
}) => sttChoicesFrom(models, l, missing: missing, own: own);

/// The Language submenu, or null where the engine picks the language itself
/// (Parakeet), as the dock and Settings hide the picker.
List<AppCommand>? languageCommandsFor(AppSettings? settings) {
  if (settings == null) return null;
  if (settings.sttProviderType.isLocal &&
      settings.onDeviceEngine == OnDeviceEngine.parakeet) {
    return null;
  }
  return buildLanguageCommands(
    activeCode: settings.sttLanguageCode,
    favoriteCodes: settings.stt.favoriteLanguages,
    autoLabelKey: 'settingsLanguageAutoDetect',
    moreLabelKey: 'trayLanguageMore',
  );
}

/// The tray command tree for the given state. The tray and the menu bar's
/// Aufnahme menu both build from this tree, so they show the same state.
List<AppCommand> trayCommandTree(
  L10n l, {
  bool historyLocked = false,
  List<({String id, String label})> recentRecordings = const [],
  required RecordingState recording,
  required List<String> micDeviceLabels,
  required AppSettings? settings,
  required List<SttChoice>? choices,
  required List<AppProfile> profiles,
  required ProfileChoice profileChoice,
  required ({String id, String label})? actionNeeded,
  required bool sidePanelAvailable,
  bool coffeeAvailable = false,
  bool resumeOnboardingAvailable = false,
  ({String id, String label})? overlayRestore,
}) {
  final locked = isDictationBusy(recording.phase);
  return buildTrayCommands(
    TrayMenuState(
      isRecording: recording.isRecording,
      isProcessing:
          trayIconStateFor(recording.phase) == TrayIconState.processing,
      micDeviceLabels: micDeviceLabels,
      selectedMic: settings?.audioInput.microphone ?? micDefaultLabel,
      languageCommands: languageCommandsFor(settings),
      speechModelCommands: settings == null
          ? null
          : buildSpeechModelCommands(
              choices: choices!,
              current: sttChoiceValue(settings),
              locked: locked,
            ),
      smartModeCommands: settings == null
          ? const []
          : buildSmartModeCommands(current: settings.smartMode.standardPreset),
      profileCommands: buildProfileCommands(
        profiles: profiles,
        current: profileChoice,
      ),
      outputCommands: settings == null
          ? const []
          : buildOutputCommands(
              current: resolveAfterTranscriptionAction(
                settings.afterTranscriptionAction,
              ),
              labelFor: (a) => afterTranscriptionStatusLabel(a, l),
              autoPasteSupported: kAutoPasteSupported,
            ),
      actionNeeded: actionNeeded,
      sidePanelAvailable: sidePanelAvailable,
      coffeeAvailable: coffeeAvailable,
      resumeOnboardingAvailable: resumeOnboardingAvailable,
      overlayRestore: overlayRestore,
      historyLocked: historyLocked,
      recentRecordings: recentRecordings,
      toggleShortcut: settings == null ? null : trayToggleShortcut(settings, l),
    ),
    trayLabelsFor(l),
  );
}

/// The tray's way back to the overlay (overlay F, #194): "Overlay einschalten"
/// while it is switched off, "Overlay wieder einblenden (bis HH:MM
/// ausgeblendet)" while the hide hour runs, else null.
@visibleForTesting
({String id, String label})? trayOverlayRestore(
  L10n l, {
  required bool overlayOn,
  required DateTime? hiddenUntil,
  required DateTime now,
}) {
  if (!overlayOn) {
    return (id: TrayCommandIds.overlayTurnOn, label: l.trayOverlayTurnOn);
  }
  if (hiddenUntil == null || !now.isBefore(hiddenUntil)) return null;
  final time = DateFormat.Hm(l.localeName).format(hiddenUntil.toLocal());
  return (
    id: TrayCommandIds.overlayShowAgain,
    label: l.trayOverlayShowAgain(time),
  );
}

/// The dictation trigger as the tray and the button menu show it: the single
/// key when one is the trigger (one trigger per action), else the
/// combination with the key the user pressed (`Ö`, not the stored physical
/// position `;`), the same text as settings and overview.
@visibleForTesting
String trayToggleShortcut(AppSettings settings, L10n l) {
  final hotkey = settings.hotkey;
  if (hotkey.hotkeyDoubleTapKey.isNotEmpty) {
    return modifierOnlyLabel(l, hotkey.hotkeyDoubleTapKey);
  }
  return formatHotkeyShortcut(
    hotkey.hotkeyModifiers,
    hotkey.hotkeyKey,
    l10n: l,
    displayOverride: hotkey.hotkeyKeyDisplay,
  );
}

/// What a tray menu shows, without the item IDs: menu_base numbers every
/// item it creates, so two builds of the same menu differ only there.
@visibleForTesting
Map<String, dynamic> trayMenuContent(Menu menu) => {
  'items': [
    for (final item in menu.items ?? const <MenuItem>[]) _itemContent(item),
  ],
};

Map<String, dynamic> _itemContent(MenuItem item) => {
  ...item.toJson()..remove('id'),
  if (item.submenu != null) 'submenu': trayMenuContent(item.submenu!),
};
