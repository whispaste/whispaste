import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/instance_cli.dart';
import 'package:whispaste/services/single_instance_service.dart';

/// Command line of a normal launch (#1952): parsing, the guards against
/// typos and unusable files, and which forwarded commands act.
void main() {
  final posix = p.Context(style: p.Style.posix, current: '/home/u');
  const existing = {'/home/u/memo.mp3', '/home/u/talk.MP4', '/home/u/a.txt'};
  const extensions = ['wav', 'mp4', 'mp3'];

  InstanceCliRequest parse(List<String> args, {bool canReadPaths = true}) =>
      parseInstanceCli(
        args,
        isFile: existing.contains,
        extensions: extensions,
        canReadPaths: canReadPaths,
        context: posix,
      );

  void expectError(InstanceCliRequest r, int code, String containing) {
    expect(r, isA<InstanceCliError>());
    final error = r as InstanceCliError;
    expect(error.exitCode, code);
    expect(error.message, contains(containing));
  }

  group('launches as usual', () {
    test('no arguments, the commands and the launch flags', () {
      for (final args in [
        const <String>[],
        const ['--start'],
        const ['--stop'],
        const ['--toggle'],
        const ['--cancel'],
        const ['--start', '--start'],
        const ['--autostart'],
        const ['--hang-restart-wait=1234'],
        const ['--import-files', r'C:\a b\talk.mpeg', '/home/u/memo.mp3'],
        const ['whispaste://newsletter/confirmed'],
      ]) {
        expect(parse(args), isA<InstanceCliLaunch>(), reason: '$args');
      }
    });

    test('files without a flag stay the file manager handover (#1684)', () {
      expect(parse(const ['/does/not/exist.xyz']), isA<InstanceCliLaunch>());
    });

    test('AppKit defaults (-Key Value) are neither commands nor files', () {
      expect(
        parse(const ['-NSDocumentRevisionsDebugMode', 'YES', '--toggle']),
        isA<InstanceCliLaunch>(),
      );
    });

    test('--transcribe with existing files of a supported type', () {
      expect(
        parse(const ['--transcribe', 'memo.mp3']),
        isA<InstanceCliLaunch>(),
      );
      expect(
        parse(const ['--transcribe', '/home/u/memo.mp3', 'talk.MP4']),
        isA<InstanceCliLaunch>(),
      );
      expect(
        parse(const ['--transcribe', 'file:///home/u/memo.mp3']),
        isA<InstanceCliLaunch>(),
      );
    });
  });

  test('--help and -h ask for the usage, which lists every command', () {
    expect(parse(const ['--help']), isA<InstanceCliHelp>());
    expect(parse(const ['-h']), isA<InstanceCliHelp>());
    expect(parse(const ['--bogus', '--help']), isA<InstanceCliHelp>());
    for (final flag in [...instanceCliCommands.keys, instanceCliTranscribe]) {
      expect(instanceCliUsage, contains(flag));
    }
  });

  group('refuses with a usage error', () {
    test('an unknown command', () {
      expectError(parse(const ['--strat']), instanceCliExitUsage, '--strat');
      expectError(parse(const ['--autostartx']), instanceCliExitUsage, '');
    });

    test('two different commands', () {
      expectError(
        parse(const ['--start', '--stop']),
        instanceCliExitUsage,
        'one command at a time',
      );
    });

    test('--transcribe without a file, or with a command', () {
      expectError(
        parse(const ['--transcribe']),
        instanceCliExitUsage,
        'needs a file',
      );
      expectError(
        parse(const ['--start', '--transcribe', 'memo.mp3']),
        instanceCliExitUsage,
        'cannot be combined',
      );
    });

    test('a command with a file', () {
      expectError(
        parse(const ['--toggle', 'memo.mp3']),
        instanceCliExitUsage,
        'takes no file',
      );
    });
  });

  group('--transcribe refuses an unusable file', () {
    test('missing', () {
      expectError(
        parse(const ['--transcribe', 'gone.mp3']),
        instanceCliExitNoInput,
        'file not found: /home/u/gone.mp3',
      );
    });

    test('of a type the import does not read', () {
      expectError(
        parse(const ['--transcribe', 'a.txt']),
        instanceCliExitNoInput,
        'file type not supported',
      );
    });

    test('where this build cannot read named files (Mac App Store)', () {
      expectError(
        parse(const ['--transcribe', 'memo.mp3'], canReadPaths: false),
        instanceCliExitNoInput,
        'open -a WhisPaste',
      );
    });
  });

  test('--start acts only when idle, --stop only while recording', () {
    expect(remoteCommandActs(InstanceCommand.start, recording: false), isTrue);
    expect(remoteCommandActs(InstanceCommand.start, recording: true), isFalse);
    expect(remoteCommandActs(InstanceCommand.stop, recording: true), isTrue);
    expect(remoteCommandActs(InstanceCommand.stop, recording: false), isFalse);
    for (final recording in [true, false]) {
      expect(
        remoteCommandActs(InstanceCommand.toggle, recording: recording),
        isTrue,
      );
      expect(
        remoteCommandActs(InstanceCommand.cancel, recording: recording),
        isTrue,
      );
    }
  });
}
