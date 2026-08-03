/// Shared dispatch substrate for dictation automations
/// (`.scratch/dictation-automations/issues/02-exact-match-dispatch-automation-url.md`).
///
/// An automation fires when the *entire* transcription exactly matches its
/// trigger phrase, after normalization ([normalizeForExactMatch]) — not
/// "contains anywhere", unlike text replacements. On a match the
/// [RecordingOrchestrator] skips insert/paste and the history entry entirely
/// and dispatches the automation's action here instead.
///
/// [AutomationActionType.openUrl] and [AutomationActionType.shellCommand]
/// exist today (ticket 03); tickets 04/06 add script and snippet-picker
/// action types onto the same `actionType`/`payload` split without a schema
/// change.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/build_config.dart';
import '../core/data/database.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('AutomationDispatchService');

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

/// Normalizes [input] for exact-match comparison: trim, collapse internal
/// whitespace runs to a single space, drop trailing punctuation, lowercase.
///
/// Applied to both the finished transcript and every automation's trigger
/// phrase before comparing them — only the *comparison* is normalized, the
/// transcript that eventually reaches history/paste is never touched by this.
String normalizeForExactMatch(String input) {
  final collapsed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  final withoutTrailingPunctuation = collapsed.replaceAll(
    RegExp(r'[.,!?;:…]+$'),
    '',
  );
  return withoutTrailingPunctuation.trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// Action types
// ---------------------------------------------------------------------------

/// The action kinds an [Automation] row's `actionType` column can hold.
enum AutomationActionType {
  openUrl('open_url'),
  shellCommand('shell_command');

  const AutomationActionType(this.dbValue);

  /// The literal string stored in `automations.action_type`.
  final String dbValue;

  static AutomationActionType? fromDbValue(String value) {
    for (final type in values) {
      if (type.dbValue == value) return type;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Finds the automation matching a transcript and executes its action.
class AutomationDispatchService {
  AutomationDispatchService({
    Future<bool> Function(Uri)? urlLauncher,
    Future<bool> Function(String)? shellCommandRunner,
    bool? isMasBuild,
  }) : _urlLauncher = urlLauncher ?? launchUrl,
       _shellCommandRunner = shellCommandRunner ?? _defaultShellCommandRunner,
       _isMasBuild = isMasBuild ?? kIsMasBuild;

  final Future<bool> Function(Uri) _urlLauncher;
  final Future<bool> Function(String) _shellCommandRunner;

  /// Gated here too, not just in the settings UI: a `shell_command`
  /// automation smuggled in via settings import must not become executable
  /// just because the sandboxed MAS build hides the action type from the
  /// picker.
  final bool _isMasBuild;

  /// Returns the automation among [automations] whose trigger exactly
  /// matches [transcript] after normalization, or `null` if none matches.
  /// An empty normalized transcript never matches (guards against an
  /// automation with an empty/whitespace-only trigger firing on silence).
  Automation? findMatch(List<Automation> automations, String transcript) {
    final normalizedTranscript = normalizeForExactMatch(transcript);
    if (normalizedTranscript.isEmpty) return null;
    for (final automation in automations) {
      if (normalizeForExactMatch(automation.trigger) == normalizedTranscript) {
        return automation;
      }
    }
    return null;
  }

  /// Executes [automation]'s action. Returns `true` when it ran
  /// successfully, `false` for an unknown action type or a failure
  /// (malformed payload, URL launch rejected, etc.) — always non-throwing.
  Future<bool> dispatch(Automation automation) async {
    final actionType = AutomationActionType.fromDbValue(automation.actionType);
    switch (actionType) {
      case AutomationActionType.openUrl:
        return _openUrl(automation.payload);
      case AutomationActionType.shellCommand:
        return _runShellCommand(automation.payload);
      case null:
        _log.warning(
          'Unknown automation action type: ${automation.actionType}',
        );
        return false;
    }
  }

  Future<bool> _openUrl(String payload) async {
    final url = decodeOpenUrlPayload(payload);
    if (url == null) {
      _log.warning('open_url automation payload missing/invalid "url"');
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _log.warning('open_url automation payload has an invalid URL');
      return false;
    }
    try {
      return await _urlLauncher(uri);
    } on Exception catch (e) {
      _log.warning('open_url automation dispatch failed: $e');
      return false;
    }
  }

  Future<bool> _runShellCommand(String payload) async {
    if (_isMasBuild) {
      _log.warning(
        'shell_command automation ignored: not available on the sandboxed '
        'Mac App Store build',
      );
      return false;
    }
    final command = decodeShellCommandPayload(payload);
    if (command == null || command.trim().isEmpty) {
      _log.warning('shell_command automation payload missing/invalid '
          '"command"');
      return false;
    }
    try {
      return await _shellCommandRunner(command);
    } on Exception catch (e) {
      _log.warning('shell_command automation dispatch failed: $e');
      return false;
    }
  }

  /// `runInShell: true` shell-quotes the executable as a single token
  /// rather than splicing [command] into a shell command line, so a command
  /// containing spaces/redirects/pipes would be looked up as one literal
  /// (nonexistent) program name. Invoking the platform shell explicitly with
  /// `-c`/`/c` is what actually interprets [command] as shell syntax.
  static Future<bool> _defaultShellCommandRunner(String command) async {
    final String shellExecutable;
    final List<String> shellArgs;
    if (Platform.isWindows) {
      shellExecutable = 'cmd.exe';
      shellArgs = ['/c', command];
    } else {
      shellExecutable = '/bin/sh';
      shellArgs = ['-c', command];
    }
    await Process.start(
      shellExecutable,
      shellArgs,
      mode: ProcessStartMode.detached,
    );
    return true;
  }
}

/// Decodes an `open_url` automation's `payload` JSON (`{"url": "..."}`) into
/// the raw URL string, or `null` if it's malformed. Shared by [dispatch] and
/// the Automations settings page, which both need to read this same shape.
String? decodeOpenUrlPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map && decoded['url'] is String) {
      return decoded['url'] as String;
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// Decodes a `shell_command` automation's `payload` JSON
/// (`{"command": "..."}`) into the raw command string, or `null` if it's
/// malformed. Shared by [dispatch] and the Automations settings page.
String? decodeShellCommandPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map && decoded['command'] is String) {
      return decoded['command'] as String;
    }
    return null;
  } on FormatException {
    return null;
  }
}

final automationDispatchServiceProvider = Provider<AutomationDispatchService>(
  (ref) => AutomationDispatchService(),
);
