/// Delivery step for WhisPaste-GPU-Probe.
///
/// After the ZIP bundle is written to the Desktop this module:
///   1. Reveals the file in the native file-manager (Finder / Explorer).
///   2. Opens the local mail client with a pre-filled `mailto:` URL.
///
/// All platform commands are constructed as pure, testable functions.
/// The actual process launch is delegated to an injectable [DeliveryLauncher]
/// seam so unit tests can capture calls without spawning real processes.
library;

import 'dart:io';

// ---------------------------------------------------------------------------
// DeliveryLauncher seam
// ---------------------------------------------------------------------------

/// Abstraction over [Process.run] so delivery tests never spawn real processes.
///
/// Named [DeliveryLauncher] (not `ProcessLauncher`) to avoid a name clash with
/// the [ProcessLauncher] typedef in `probe_runner.dart` which has a different
/// signature.
typedef DeliveryLauncher =
    Future<void> Function(String executable, List<String> arguments);

/// Default production [DeliveryLauncher] — delegates to [Process.run].
///
/// Explorer's exit code is unreliable on Windows so we ignore the result.
Future<void> defaultDeliveryLauncher(
  String executable,
  List<String> arguments,
) async {
  await Process.run(executable, arguments);
}

// ---------------------------------------------------------------------------
// Reveal command
// ---------------------------------------------------------------------------

/// Returns the executable and argument list that reveals [zipPath] in the
/// native file manager.
///
/// - macOS: `open -R <zipPath>`
/// - Windows: `explorer /select,<zipPath>`
///   (Note: `explorer.exe` returns unreliable exit codes — do **not** assert
///   on the exit code.)
/// - Other (Linux …): falls back to `xdg-open` on the parent directory.
///
/// [platform] defaults to [Platform.operatingSystem]; inject for tests.
({String executable, List<String> arguments}) revealCommand(
  String zipPath, {
  String? platform,
}) {
  final os = platform ?? Platform.operatingSystem;
  return switch (os) {
    'macos' => (executable: 'open', arguments: ['-R', zipPath]),
    'windows' => (executable: 'explorer', arguments: ['/select,$zipPath']),
    _ => (executable: 'xdg-open', arguments: [File(zipPath).parent.path]),
  };
}

// ---------------------------------------------------------------------------
// Mailto URL builder
// ---------------------------------------------------------------------------

/// Builds a `mailto:` URL for the WhisPaste-GPU-Probe support mail.
///
/// All query parameters are percent-encoded so that clients (Mail.app,
/// Outlook, Thunderbird …) parse them correctly.
///
/// Parameters are injectable so the function is fully unit-testable without
/// side-effects.
String buildMailtoUrl({
  String to = 'silvio-lindstedt@outlook.com',
  String subject = 'GPU-Probe-Report',
  String body =
      'Hallo,\n\nanbei mein WhisPaste GPU-Probe-Report.\n'
      'Bitte die ZIP-Datei vom Desktop anhängen.\n\n'
      'Viele Grüße',
}) {
  final encodedTo = Uri.encodeComponent(to);
  final encodedSubject = Uri.encodeComponent(subject);
  final encodedBody = Uri.encodeComponent(body);
  return 'mailto:$encodedTo?subject=$encodedSubject&body=$encodedBody';
}

// ---------------------------------------------------------------------------
// Mail-open command
// ---------------------------------------------------------------------------

/// Returns the executable and argument list that opens [mailtoUrl] in the
/// local mail client.
///
/// - macOS: `open <mailtoUrl>`
/// - Windows: `cmd /c start "" <mailtoUrl>`
/// - Other: `xdg-open <mailtoUrl>`
///
/// [platform] defaults to [Platform.operatingSystem]; inject for tests.
({String executable, List<String> arguments}) mailOpenCommand(
  String mailtoUrl, {
  String? platform,
}) {
  final os = platform ?? Platform.operatingSystem;
  return switch (os) {
    'macos' => (executable: 'open', arguments: [mailtoUrl]),
    'windows' => (executable: 'cmd', arguments: ['/c', 'start', '', mailtoUrl]),
    _ => (executable: 'xdg-open', arguments: [mailtoUrl]),
  };
}

// ---------------------------------------------------------------------------
// Top-level delivery entry point
// ---------------------------------------------------------------------------

/// Performs the post-report delivery step:
///   1. Reveals [zipPath] in the native file manager.
///   2. Opens the local mail client with a pre-filled support mail.
///
/// [platform] and [launcher] are injectable for tests.
Future<void> deliverReport(
  String zipPath, {
  String? platform,
  DeliveryLauncher? launcher,
}) async {
  final launch = launcher ?? defaultDeliveryLauncher;

  // 1. Reveal the ZIP in Finder / Explorer.
  final reveal = revealCommand(zipPath, platform: platform);
  await launch(reveal.executable, reveal.arguments);

  // 2. Open the local mail client.
  final mailtoUrl = buildMailtoUrl();
  final mail = mailOpenCommand(mailtoUrl, platform: platform);
  await launch(mail.executable, mail.arguments);
}
