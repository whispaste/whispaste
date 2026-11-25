/// The diagnostics a feedback message can carry (FB-04), only on opt-in.
///
/// The short block names app version, operating system, the speech engine
/// (the cloud service when one transcribes) and the compute backend; it names
/// no model. The attachment ([buildFeedbackDiagnosticAttachment]) adds
/// sanitized recent log lines, bounded to 64 KiB, and travels as a separate
/// `diagnostics` field, never in the 1000-character message text.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    as diagnostics;

import '../core/app_info.dart';
import '../core/config/settings_enums.dart'
    show OnDeviceEngine, SttProviderType;
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart' show logFilePath;
import '../core/logging/crash_error_redaction.dart' show redactPathsInText;
import 'stt/whisper/whisper_isolate_engine.dart' show whisperEngineProvider;

/// Builds the block from plain values. Pure, so the exact text is testable.
String buildFeedbackDiagnosticBlock({
  required String appVersion,
  required String os,
  required String engine,
  required String backend,
}) =>
    '--- diagnostics ---\n'
    'App $appVersion · OS $os · Engine $engine · Backend $backend';

/// The block for this machine and the current settings. Reads the live
/// engine state, so a switch of engine or backend shows up on the next build.
///
/// With a cloud transcription service the block names that service and the
/// backend `cloud`: the on-device engine does not run then, and naming it sent
/// a report of a cloud setup as a local one (#2116).
final feedbackDiagnosticBlockProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final cloudEngine = feedbackCloudEngineName(settings.sttProviderType);
  if (cloudEngine != null) {
    return buildFeedbackDiagnosticBlock(
      appVersion: appVersion,
      os: feedbackShortOs(),
      engine: cloudEngine,
      backend: 'cloud',
    );
  }
  final engine = settings.onDeviceEngine;
  final backend = engine == OnDeviceEngine.parakeet
      ? 'cpu'
      : ref.watch(whisperEngineProvider).status.deviceBackend.name;
  return buildFeedbackDiagnosticBlock(
    appVersion: appVersion,
    os: feedbackShortOs(),
    engine: engine.value,
    backend: backend,
  );
});

/// The engine name of a cloud transcription [provider] in the block, or null
/// for the on-device one. Names the service only, never an address or a key.
String? feedbackCloudEngineName(SttProviderType provider) => switch (provider) {
  SttProviderType.onDevice => null,
  SttProviderType.openAI => 'openai',
  SttProviderType.deepgram => 'deepgram',
  SttProviderType.customEndpoint => 'custom-endpoint',
};

/// The operating system name and its version, cut to one short line. Linux
/// kernel strings run long, and the block has to stay short. The onboarding
/// contact panel sends the same line with its technical details.
String feedbackShortOs() {
  final version = Platform.operatingSystemVersion.split('\n').first.trim();
  final cut = version.length > 40 ? version.substring(0, 40) : version;
  return '${Platform.operatingSystem} $cut'.trim();
}

/// Upper bound of the attachment in UTF-8 bytes. The API takes at most
/// 65,536 bytes in `diagnostics`.
const kFeedbackDiagnosticsMaxBytes = 65536;

/// Longest log line the attachment keeps. Log lines carry events, ids and
/// lengths; a longer line is cut, so a stray block of text cannot travel whole.
const kFeedbackLogLineMaxChars = 400;

/// Secret shapes beyond the shared log filter
/// ([diagnostics.containsSensitiveData]): a line that matches one is left out
/// of the attachment entirely.
final List<RegExp> _attachmentSecretPatterns = [
  // JSON Web Tokens (session and access tokens).
  RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
  // Access tokens of code hosts and model hubs.
  RegExp(r'\b(?:hf|ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}'),
  RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}'),
  RegExp(r'\bxox[abposr]-[A-Za-z0-9-]{10,}'),
  RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
  // Named secrets in key=value or JSON form.
  RegExp(
    r'''["']?(?:[a-z_-]*secret|private[_-]?key|cookie|session[_-]?id|signature)["']?\s*[:=]\s*\S+''',
    caseSensitive: false,
  ),
  // Credentials in URL query strings.
  RegExp(
    r'[?&](?:key|sig|signature|auth|code|access_token)=[^\s&]+',
    caseSensitive: false,
  ),
];

/// E-mail addresses.
final RegExp _emailAddress = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}',
);

/// Fields that can hold dictated or copied text, in key=value or JSON form.
/// Their value becomes `<text>`, up to the closing quote or, unquoted, to the
/// end of the line.
final RegExp _textField = RegExp(
  r'''(["']?\b(?:text|transcript|transcription|content|clipboard|prompt|input|output|snippet|note|body|message)["']?\s*[:=]\s*)(?:"(?:[^"\\]|\\.)*"?|'(?:[^'\\]|\\.)*'?|[^\s,}\]][^,}\]]*)''',
  caseSensitive: false,
);

/// Quoted text with a space in it, at least 12 characters: how a sentence
/// appears in an error message. Becomes `"<text>"`.
final RegExp _quotedProse = RegExp(
  '(["\u201C\u201E\u00AB])([^"\u201C\u201D\u201E\u00AB\u00BB\n]*\\s[^"\u201C\u201D\u201E\u00AB\u00BB\n]*)(["\u201C\u201D\u00BB])',
);

/// One log line as it may leave the device, or `null` when it is left out.
///
/// Logs already hold no dictated text or clipboard content by design (only
/// lengths, ids and error kinds, see `errorKind`); this filter is the second
/// line of defence for a line that slipped through:
/// - lines with a secret (API key, token, password, bearer, JWT, hub token,
///   named secret, credential in a URL) are dropped;
/// - e-mail addresses become `<email>`;
/// - text fields (`text=`, `"transcript":`, `clipboard:` …) and quoted
///   sentences become `<text>`;
/// - paths become `<path>`/`<file>.<ext>`, account names `<user>`, the home
///   folder `~` (same rules as crash reports);
/// - the line is cut after [kFeedbackLogLineMaxChars] characters.
String? sanitizeFeedbackLogLine(String line) {
  if (diagnostics.containsSensitiveData(line)) return null;
  if (_attachmentSecretPatterns.any((p) => p.hasMatch(line))) return null;
  var out = line.replaceAll(_emailAddress, '<email>');
  out = out.replaceAllMapped(_textField, (m) => '${m[1]}<text>');
  out = out.replaceAllMapped(_quotedProse, (m) {
    final inner = m[2]!;
    return inner.length < 12 ? m[0]! : '${m[1]}<text>${m[3]}';
  });
  out = diagnostics.sanitizePaths(redactPathsInText(out));
  if (out.length > kFeedbackLogLineMaxChars) {
    out = '${out.substring(0, kFeedbackLogLineMaxChars)}… <cut>';
  }
  return out;
}

/// The opt-in attachment: the short [summary] block, then the most recent
/// log lines (previous sessions included, oldest first), each passed through
/// [sanitizeFeedbackLogLine], bounded to [kFeedbackDiagnosticsMaxBytes]. Only
/// complete lines are kept; the oldest go first when the limit is reached.
String buildFeedbackDiagnosticAttachment(
  String summary,
  Iterable<String> lines,
) {
  final header =
      '$summary\n\n--- recent logs (including previous sessions) ---\n';
  final selected = <String>[];
  var bytes = utf8.encode(header).length;
  for (final line in lines.toList().reversed) {
    final safe = sanitizeFeedbackLogLine(line);
    if (safe == null) continue;
    final size = utf8.encode('$safe\n').length;
    if (bytes + size > kFeedbackDiagnosticsMaxBytes) break;
    selected.add(safe);
    bytes += size;
  }
  return '$header${selected.reversed.join('\n')}';
}

/// The attachment for this machine. Reads the log files only when read, which
/// happens only after the user ticked "Attach diagnostics"; callers
/// invalidate it on each tick so the preview and the send show fresh lines.
final feedbackDiagnosticAttachmentProvider = Provider<String>((ref) {
  final summary = ref.watch(feedbackDiagnosticBlockProvider);
  final logs = diagnostics.readFullLog(logFilePath: logFilePath);
  return buildFeedbackDiagnosticAttachment(summary, logs.lines);
});
