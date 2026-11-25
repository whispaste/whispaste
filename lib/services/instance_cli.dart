/// The command line of a normal WhisPaste launch (#1952): the documented
/// commands that drive the running instance, `--help`, and the guard that
/// turns a typo into a clear message instead of a silent window launch.
///
/// The commands themselves travel over the single-instance channel
/// ([SingleInstanceService]); files for `--transcribe` take the same path as
/// the file manager's "Transcribe with WhisPaste" entry (#1684), so this
/// file only checks the command line before anything starts.
///
/// - `--start`, `--stop`, `--toggle`, `--cancel`: [InstanceCommand]s.
/// - `--transcribe <file>…`: hands the files to the normal file import.
/// - `-h`, `--help`: prints [instanceCliUsage].
///
/// Output stays English, like every other `whispaste` command line
/// (`--diagnose`, `--transcribe-file`): it is read in terminals and scripts,
/// and its words match the documented flags.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/config/build_config.dart' show kIsMasBuild;
import 'audio/import/audio_file_decoder.dart' show supportedImportExtensions;
import 'opened_files.dart';
import 'single_instance_service.dart';

/// Exit code for an unknown command or a wrong combination (`EX_USAGE`,
/// same as the headless command lines).
const int instanceCliExitUsage = 64;

/// Exit code for a file to transcribe that cannot be used (`EX_NOINPUT`):
/// missing, not a file, or of a type the import does not read.
const int instanceCliExitNoInput = 66;

/// Printed for `--help` and after a usage error.
const String instanceCliUsage = '''
Usage: whispaste [command]

Controls the running WhisPaste. No second window opens: the command goes to
the WhisPaste that is already running. If none runs, --start, --toggle and
--transcribe start it first; --stop and --cancel then do nothing.

Commands:
  --start               Start a dictation (nothing if one is running).
  --stop                Stop the dictation and transcribe it.
  --toggle              Start a dictation, or stop the running one.
  --cancel              Discard the running dictation.
  --transcribe <file>   Transcribe audio or video files, like "Add files".
                        Several files are allowed.
  -h, --help            Show this help.

Exit codes: 0 handed to WhisPaste, 64 unknown command or wrong use,
66 file missing or of an unsupported type.
''';

/// Printed after a usage error, under the message.
const String instanceCliHelpHint = 'Run "whispaste --help" for the commands.';

/// The flags that drive the running instance, by flag.
const Map<String, InstanceCommand> instanceCliCommands = {
  '--start': InstanceCommand.start,
  '--stop': InstanceCommand.stop,
  '--toggle': InstanceCommand.toggle,
  '--cancel': InstanceCommand.cancel,
};

/// The `--transcribe` flag.
const String instanceCliTranscribe = '--transcribe';

/// Flags the system or WhisPaste itself puts on a normal launch. They are
/// not commands and must never be refused, or the app would not start.
/// Register every new launch flag here (exact flag, or prefix ending in
/// `=` for flags with an attached value).
const List<String> instanceCliLaunchFlags = [
  // Login item / autostart entry on every system.
  '--autostart',
  // Windows hang watchdog restart (hang_watchdog_host.cpp).
  '--hang-restart-wait=',
  // Windows Explorer command (windows/shell/explorer_command.cpp): the
  // absolute paths that follow go through FileImportInbox (#2069).
  '--import-files',
];

/// What the command line of a normal launch asks for.
sealed class InstanceCliRequest {
  const InstanceCliRequest();
}

/// Start (or signal the running instance) as usual: [InstanceCommand.fromArgs]
/// and [openedFilesFromArgs] read the arguments.
final class InstanceCliLaunch extends InstanceCliRequest {
  const InstanceCliLaunch();
}

/// `--help`: print [instanceCliUsage] and exit 0.
final class InstanceCliHelp extends InstanceCliRequest {
  const InstanceCliHelp();
}

/// A command line that cannot be carried out: print [message] to stderr and
/// exit with [exitCode]. Nothing is started or signalled.
final class InstanceCliError extends InstanceCliRequest {
  const InstanceCliError(this.message, this.exitCode);

  final String message;
  final int exitCode;
}

/// [parseInstanceCli] against this system: real files, the import's types,
/// and the Mac App Store sandbox.
InstanceCliRequest checkLaunchCommandLine(List<String> args) =>
    parseInstanceCli(
      args,
      isFile: (path) =>
          FileSystemEntity.typeSync(path) == FileSystemEntityType.file,
      extensions: supportedImportExtensions(),
      canReadPaths: !(Platform.isMacOS && kIsMasBuild),
    );

/// Checks the launch [args] (#1952).
///
/// [isFile] tells whether a path names an existing file (tests inject it).
/// [extensions] are the types the file import reads
/// (`supportedImportExtensions`). [canReadPaths] is false where this
/// process cannot read files named on the command line (the sandboxed Mac
/// App Store build): `--transcribe` then explains the way that works.
InstanceCliRequest parseInstanceCli(
  List<String> args, {
  required bool Function(String path) isFile,
  required List<String> extensions,
  bool canReadPaths = true,
  p.Context? context,
}) {
  InstanceCommand? command;
  String? commandFlag;
  var transcribe = false;
  final files = <String>[];
  // Help wins over everything else on the line, typos included.
  if (args.any((arg) => arg == '--help' || arg == '-h')) {
    return const InstanceCliHelp();
  }
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final remote = instanceCliCommands[arg];
    if (remote != null) {
      if (command != null && command != remote) {
        return InstanceCliError(
          'whispaste: use one command at a time ($commandFlag and $arg)',
          instanceCliExitUsage,
        );
      }
      command = remote;
      commandFlag = arg;
      continue;
    }
    if (arg == instanceCliTranscribe) {
      transcribe = true;
      continue;
    }
    if (_isLaunchFlag(arg)) continue;
    if (arg.startsWith('--')) {
      return InstanceCliError(
        'whispaste: unknown command "$arg"',
        instanceCliExitUsage,
      );
    }
    if (arg.startsWith('-')) {
      // AppKit passes defaults as `-Key Value` (Xcode:
      // `-NSDocumentRevisionsDebugMode YES`); neither part is a file.
      if (i + 1 < args.length && !args[i + 1].startsWith('-')) i++;
      continue;
    }
    final file = openedFileFromArg(arg, context: context);
    if (file != null) files.add(file);
  }

  if (transcribe && command != null) {
    return InstanceCliError(
      'whispaste: $instanceCliTranscribe cannot be combined with $commandFlag',
      instanceCliExitUsage,
    );
  }
  if (command != null && files.isNotEmpty) {
    return InstanceCliError(
      'whispaste: $commandFlag takes no file; use $instanceCliTranscribe '
      '<file>',
      instanceCliExitUsage,
    );
  }
  if (!transcribe) return const InstanceCliLaunch();

  if (files.isEmpty) {
    return const InstanceCliError(
      'whispaste: $instanceCliTranscribe needs a file',
      instanceCliExitUsage,
    );
  }
  if (!canReadPaths) {
    return const InstanceCliError(
      'whispaste: the Mac App Store version cannot open files named on the '
      'command line. Use: open -a WhisPaste <file>',
      instanceCliExitNoInput,
    );
  }
  final ctx = context ?? p.context;
  final accepted = {for (final e in extensions) e.toLowerCase()};
  for (final file in files) {
    if (!isFile(file)) {
      return InstanceCliError(
        'whispaste: file not found: $file',
        instanceCliExitNoInput,
      );
    }
    final ext = ctx.extension(file).replaceFirst('.', '').toLowerCase();
    if (!accepted.contains(ext)) {
      return InstanceCliError(
        'whispaste: file type not supported: $file '
        '(supported: ${extensions.join(', ')})',
        instanceCliExitNoInput,
      );
    }
  }
  return const InstanceCliLaunch();
}

/// Whether a forwarded [command] acts while the dictation is [recording]:
/// `--start` only when none records, `--stop` only when one does. The
/// other commands always reach their handler.
bool remoteCommandActs(InstanceCommand command, {required bool recording}) =>
    switch (command) {
      InstanceCommand.start => !recording,
      InstanceCommand.stop => recording,
      _ => true,
    };

bool _isLaunchFlag(String arg) {
  for (final flag in instanceCliLaunchFlags) {
    if (flag.endsWith('=') ? arg.startsWith(flag) : arg == flag) return true;
  }
  return false;
}
