/// Bridge to the native `NSUserUnixTask`-based script execution for the MAS
/// "script" automation action type
/// (`.scratch/dictation-automations/issues/04-automation-skript-editor-mas.md`).
///
/// The app cannot write into `applicationScriptsDirectory` itself — not even
/// via a save dialog, see the ticket's design-correction note — so there is
/// no "install" method here. The user drops their script in via Finder
/// ([revealScriptsFolder]); this service only lists what's already there
/// ([listScripts]) and executes it ([runScript]).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('ScriptAutomationService');

class ScriptAutomationService {
  ScriptAutomationService();

  static const _channel = MethodChannel('com.whispaste.script_automation');

  bool get isSupported => Platform.isMacOS;

  /// Reveals the app's `applicationScriptsDirectory` in Finder.
  Future<void> revealScriptsFolder() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('revealScriptsFolder');
    } on PlatformException catch (e) {
      _log.warning('revealScriptsFolder failed: $e');
    } on MissingPluginException catch (e) {
      _log.debug('revealScriptsFolder: not registered on this build: $e');
    }
  }

  /// Lists the filenames currently in `applicationScriptsDirectory`. Empty
  /// on non-macOS, lookup failure, or an empty folder.
  Future<List<String>> listScripts() async {
    if (!isSupported) return const <String>[];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listScripts');
      if (raw == null) return const <String>[];
      return raw.whereType<String>().toList(growable: false);
    } on PlatformException catch (e) {
      _log.warning('listScripts failed: $e');
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  /// Executes the script named [scriptName] (must already exist inside
  /// `applicationScriptsDirectory`, executable) via `NSUserUnixTask`. Returns
  /// `true` on success.
  ///
  /// The native side only replies once the script *exits* — an unbounded
  /// await here would let a long-running or hung user script (a stray
  /// `sleep`, a `read` waiting on stdin) freeze the whole dictation pipeline
  /// indefinitely, since the caller (`AutomationDispatchService`) awaits this
  /// before returning to idle. Same grace-window reasoning as
  /// `_defaultShellCommandRunner` for `shell_command`: judge success within a
  /// short window, treat "still running after that" as launched successfully
  /// rather than blocking on real completion. The native task itself keeps
  /// running either way — this only bounds how long *we* wait for its result.
  Future<bool> runScript(String scriptName) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('runScript', {'scriptName': scriptName})
          .timeout(const Duration(milliseconds: 800), onTimeout: () => true);
      return ok ?? false;
    } on PlatformException catch (e) {
      _log.warning('runScript($scriptName) failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
