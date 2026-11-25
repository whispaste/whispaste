/// The check a user model passes before it can be used (#1789): the format
/// check ([inspectUserModel]) and then a short test on the real runtime — a
/// short spoken clip for speech, a short instruction for Smart Mode.
///
/// This file has the check itself, without any process handling. Where it
/// runs is decided in `user_model_checker.dart`: in a child process outside
/// the Mac App Store build, in an isolate plus this process (with a crash
/// marker) inside it.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../smart_mode/smart_mode_ffi_engine.dart' show SmartModeFfiEngine;
import '../stt/whisper/whisper_isolate_engine.dart' show WhisperIsolateEngine;
import 'user_model.dart';
import 'user_model_inspector.dart';
import 'user_sherpa_engine.dart';

final _log = AppLogger('UserModelCheck');

/// What the check found.
class UserModelCheckReport {
  const UserModelCheckReport({required this.inspection, this.testFailure});

  final InspectionResult inspection;

  /// Why the short test failed; null when it passed or did not run.
  final UserModelFailure? testFailure;

  bool get ok => inspection.ok && testFailure == null;

  UserModelFailure? get failure => inspection.failure ?? testFailure;

  Map<String, Object?> toJson() => {
    'inspection': inspection.toJson(),
    'test_failure': ?testFailure?.value,
  };

  static UserModelCheckReport fromJson(Object? json) {
    if (json is! Map) {
      return const UserModelCheckReport(
        inspection: InspectionResult.failed(UserModelFailure.checkUnavailable),
      );
    }
    return UserModelCheckReport(
      inspection: InspectionResult.fromJson(json['inspection']),
      testFailure: UserModelFailure.fromValue(json['test_failure']),
    );
  }
}

/// Runs the short test of [model] in [dir] and returns why it failed, or
/// null when it passed. [clip] is WhisPaste's canonical 16 kHz mono PCM16
/// WAV (the spoken benchmark clip).
typedef UserModelShortTest =
    Future<UserModelFailure?> Function(
      UserModel model,
      String dir,
      Uint8List clip,
    );

/// The instruction of the Smart Mode short test.
const kSmartModeShortTestSystemPrompt =
    'You are a writing assistant. Answer with one short sentence.';
const kSmartModeShortTestUserText = 'Say hello to the user.';

/// The real short test on the bundled runtimes.
Future<UserModelFailure?> runUserModelShortTest(
  UserModel model,
  String dir,
  Uint8List clip,
) async {
  final main = model.fileFor(UserModelFileRole.model);
  try {
    switch (model.runtime) {
      case UserModelRuntime.whispercpp:
        final engine = WhisperIsolateEngine();
        try {
          await engine.load(modelPath: p.join(dir, main!.name));
          final text = await engine.transcribe(clip);
          return text.trim().isEmpty ? UserModelFailure.shortTestEmpty : null;
        } finally {
          await engine.unload();
        }
      case UserModelRuntime.sherpaOnnx:
        final engine = UserSherpaEngine(model: model, dir: dir);
        try {
          await engine.start(cores: Platform.numberOfProcessors);
          final text = await engine.transcribe(
            clip,
            timeout: const Duration(minutes: 2),
          );
          return text.trim().isEmpty ? UserModelFailure.shortTestEmpty : null;
        } finally {
          await engine.stop();
        }
      case UserModelRuntime.llamaCpp:
        final engine = SmartModeFfiEngine(modelPath: p.join(dir, main!.name));
        try {
          final text = await engine.run(
            systemPrompt: kSmartModeShortTestSystemPrompt,
            userText: kSmartModeShortTestUserText,
          );
          return text.trim().isEmpty ? UserModelFailure.shortTestEmpty : null;
        } finally {
          await engine.shutdown();
        }
    }
  } on Object catch (e) {
    _log.warning('Short test of ${model.id} failed: $e');
    return UserModelFailure.shortTestFailed;
  }
}

/// Format check in an isolate, then — only when it passed — the short test
/// in this process. The caller decides which process "this" is.
Future<UserModelCheckReport> runUserModelCheck(
  UserModel model,
  String dir, {
  required Future<Uint8List> Function() clip,
  UserModelShortTest shortTest = runUserModelShortTest,
}) async {
  final inspection = await Isolate.run(() => inspectUserModel(model, dir));
  if (!inspection.ok) return UserModelCheckReport(inspection: inspection);
  final failure = await shortTest(model, dir, await clip());
  return UserModelCheckReport(inspection: inspection, testFailure: failure);
}
