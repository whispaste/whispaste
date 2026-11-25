/// Format check of a user model's files before any runtime loads them
/// (#1789): magic bytes and header of GGUF (architecture, chat template),
/// whisper.cpp GGML (hyper-parameters) and ONNX, plus a readable tokens file
/// or BPE tokenizer.
///
/// Pure Dart file reads, no native code, so it is safe to run in an isolate
/// or the check child. Synchronous on purpose: it runs off the UI isolate.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'user_model.dart';

/// Outcome of the format check.
class InspectionResult {
  const InspectionResult.ok({this.architecture}) : failure = null;
  const InspectionResult.failed(this.failure, {this.architecture});

  final UserModelFailure? failure;

  /// GGUF `general.architecture`, or `whisper` for a GGML file.
  final String? architecture;

  bool get ok => failure == null;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'failure': ?failure?.value,
    'architecture': ?architecture,
  };

  static InspectionResult fromJson(Object? json) {
    if (json is! Map) {
      return const InspectionResult.failed(UserModelFailure.checkUnavailable);
    }
    final arch = json['architecture'] is String
        ? json['architecture'] as String
        : null;
    if (json['ok'] == true) return InspectionResult.ok(architecture: arch);
    return InspectionResult.failed(
      UserModelFailure.fromValue(json['failure']) ??
          UserModelFailure.checkUnavailable,
      architecture: arch,
    );
  }
}

/// GGUF architectures that are not text generators (embedding models,
/// encoders, vision or audio projectors). llama.cpp opens them, but they
/// cannot answer an instruction, so Smart Mode refuses them up front. Any
/// other architecture goes on to the short test, which is the real proof.
const Set<String> kNonGenerativeGgufArchitectures = {
  'bert',
  'nomic-bert',
  'nomic-bert-moe',
  'neo-bert',
  'jina-bert-v2',
  'jina-bert-v3',
  'modern-bert',
  'eurobert',
  't5encoder',
  'clip',
  'wavtokenizer-dec',
  'whisper',
  'gemma-embedding',
};

/// Checks all files of [model] in [dir].
InspectionResult inspectUserModel(UserModel model, String dir) {
  for (final f in model.files) {
    if (!File('$dir${Platform.pathSeparator}${f.name}').existsSync()) {
      return const InspectionResult.failed(UserModelFailure.missingFiles);
    }
  }
  String path(UserModelFile f) => '$dir${Platform.pathSeparator}${f.name}';
  try {
    switch (model.runtime) {
      case UserModelRuntime.llamaCpp:
        final file = model.fileFor(UserModelFileRole.model);
        if (file == null) {
          return const InspectionResult.failed(UserModelFailure.missingFiles);
        }
        return inspectGguf(path(file));
      case UserModelRuntime.whispercpp:
        final file = model.fileFor(UserModelFileRole.model);
        if (file == null) {
          return const InspectionResult.failed(UserModelFailure.missingFiles);
        }
        return inspectWhisperGgml(path(file));
      case UserModelRuntime.sherpaOnnx:
        final family = model.family;
        if (family == null) {
          return const InspectionResult.failed(UserModelFailure.badFormat);
        }
        for (final role in family.requiredRoles) {
          final file = model.fileFor(role);
          if (file == null) {
            return const InspectionResult.failed(UserModelFailure.missingFiles);
          }
          final result = switch (role) {
            UserModelFileRole.tokens => inspectTokens(path(file)),
            UserModelFileRole.tokenizerVocab ||
            UserModelFileRole.tokenizerConfig => inspectJsonObject(path(file)),
            UserModelFileRole.tokenizerMerges => inspectBpeMerges(path(file)),
            _ => inspectOnnx(path(file)),
          };
          if (!result.ok) return result;
        }
        return const InspectionResult.ok();
    }
  } on FileSystemException {
    return const InspectionResult.failed(UserModelFailure.missingFiles);
  }
}

// ---------------------------------------------------------------------------
// GGUF
// ---------------------------------------------------------------------------

const _ggufMagic = 0x46554747; // "GGUF" little-endian

/// Reads the GGUF header: magic, version, and the metadata keys
/// `general.architecture` and `tokenizer.chat_template`.
InspectionResult inspectGguf(String path) {
  final reader = _FileReader(File(path).openSync());
  try {
    if (reader.u32() != _ggufMagic) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    final version = reader.u32();
    if (version < 2 || version > 3) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    reader.u64(); // tensor count
    final kvCount = reader.u64();
    if (kvCount <= 0 || kvCount > 100000) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    String? architecture;
    var hasTemplate = false;
    for (var i = 0; i < kvCount; i++) {
      final key = reader.ggufString();
      final type = reader.u32();
      if (key == 'general.architecture' && type == 8) {
        architecture = reader.ggufString();
      } else if (key == 'tokenizer.chat_template' && type == 8) {
        hasTemplate = reader.ggufString().trim().isNotEmpty;
      } else {
        reader.skipGgufValue(type);
      }
      if (architecture != null && hasTemplate) break;
    }
    if (architecture == null || architecture.isEmpty) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    if (kNonGenerativeGgufArchitectures.contains(architecture)) {
      return InspectionResult.failed(
        UserModelFailure.unsupportedArchitecture,
        architecture: architecture,
      );
    }
    if (!hasTemplate) {
      return InspectionResult.failed(
        UserModelFailure.noChatTemplate,
        architecture: architecture,
      );
    }
    return InspectionResult.ok(architecture: architecture);
  } on _ReadPastEnd {
    return const InspectionResult.failed(UserModelFailure.badFormat);
  } on FormatException {
    return const InspectionResult.failed(UserModelFailure.badFormat);
  } finally {
    reader.close();
  }
}

// ---------------------------------------------------------------------------
// whisper.cpp GGML
// ---------------------------------------------------------------------------

const _ggmlMagic = 0x67676d6c; // "ggml" as whisper.cpp writes it (LE u32)

/// Reads the whisper.cpp header and checks its hyper-parameters are those of
/// a Whisper model (vocabulary, mel bins, layer sizes).
InspectionResult inspectWhisperGgml(String path) {
  final reader = _FileReader(File(path).openSync());
  try {
    if (reader.u32() != _ggmlMagic) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    final hp = [for (var i = 0; i < 11; i++) reader.i32()];
    final nVocab = hp[0];
    final nAudioState = hp[2];
    final nAudioLayer = hp[4];
    final nTextState = hp[6];
    final nMels = hp[9];
    final plausible =
        nVocab >= 51864 &&
        nVocab <= 51866 &&
        (nMels == 80 || nMels == 128) &&
        nAudioState > 0 &&
        nAudioState <= 4096 &&
        nAudioLayer > 0 &&
        nAudioLayer <= 64 &&
        nTextState == nAudioState;
    if (!plausible) {
      return const InspectionResult.failed(
        UserModelFailure.unsupportedArchitecture,
      );
    }
    return const InspectionResult.ok(architecture: 'whisper');
  } on _ReadPastEnd {
    return const InspectionResult.failed(UserModelFailure.badFormat);
  } finally {
    reader.close();
  }
}

// ---------------------------------------------------------------------------
// ONNX and tokens
// ---------------------------------------------------------------------------

/// An ONNX file is a protobuf `ModelProto` whose first field is
/// `ir_version` (field 1, varint), in practice 3 to 12.
InspectionResult inspectOnnx(String path) {
  final raf = File(path).openSync();
  try {
    final head = raf.readSync(16);
    if (head.length < 2 || head[0] != 0x08) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    final ir = head[1];
    if (ir < 3 || ir > 20) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    return const InspectionResult.ok();
  } finally {
    raf.closeSync();
  }
}

/// sherpa-onnx tokens: UTF-8 lines of `<symbol> <id>` (the symbol may be
/// missing for a space token).
InspectionResult inspectTokens(String path) {
  final raf = File(path).openSync();
  try {
    final head = raf.readSync(4096);
    final String text;
    try {
      text = utf8.decode(head, allowMalformed: false);
    } on FormatException {
      // A cut in the middle of a multi-byte character at the 4 KiB edge.
      final trimmed = utf8.decode(head, allowMalformed: true);
      return _tokensLook(trimmed);
    }
    return _tokensLook(text);
  } finally {
    raf.closeSync();
  }
}

InspectionResult _tokensLook(String text) {
  final lines = const LineSplitter()
      .convert(text)
      .where((l) => l.trim().isNotEmpty)
      .take(20)
      .toList();
  if (lines.length < 2) {
    return const InspectionResult.failed(UserModelFailure.badFormat);
  }
  final pattern = RegExp(r'^.*\s\d+$');
  final good = lines.where(pattern.hasMatch).length;
  return good >= lines.length - 1
      ? const InspectionResult.ok()
      : const InspectionResult.failed(UserModelFailure.badFormat);
}

/// A tokenizer JSON file (`vocab.json`, `tokenizer_config.json`): one JSON
/// object. Read whole; these files are a few MB at most.
InspectionResult inspectJsonObject(String path) {
  try {
    final data = jsonDecode(File(path).readAsStringSync());
    return data is Map && data.isNotEmpty
        ? const InspectionResult.ok()
        : const InspectionResult.failed(UserModelFailure.badFormat);
  } on FormatException {
    return const InspectionResult.failed(UserModelFailure.badFormat);
  }
}

/// BPE merges (`merges.txt`): UTF-8 lines of two symbols, after an optional
/// `#version` line.
InspectionResult inspectBpeMerges(String path) {
  final raf = File(path).openSync();
  try {
    final text = utf8.decode(raf.readSync(4096), allowMalformed: true);
    final lines = const LineSplitter()
        .convert(text)
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .take(20)
        .toList();
    if (lines.length < 2) {
      return const InspectionResult.failed(UserModelFailure.badFormat);
    }
    final good = lines.where((l) => l.trim().split(' ').length == 2).length;
    return good >= lines.length - 1
        ? const InspectionResult.ok()
        : const InspectionResult.failed(UserModelFailure.badFormat);
  } finally {
    raf.closeSync();
  }
}

// ---------------------------------------------------------------------------
// Buffered little-endian reader
// ---------------------------------------------------------------------------

class _ReadPastEnd implements Exception {
  const _ReadPastEnd();
}

class _FileReader {
  _FileReader(this._raf);

  final RandomAccessFile _raf;
  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  static const _chunk = 1 << 20;

  /// Longest single string accepted (chat templates run to a few hundred
  /// KiB; anything far beyond is a damaged file).
  static const _maxString = 16 << 20;

  void close() => _raf.closeSync();

  void _ensure(int n) {
    if (_buf.length - _pos >= n) return;
    final rest = _buf.sublist(_pos);
    final more = _raf.readSync(n > _chunk ? n : _chunk);
    final next = Uint8List(rest.length + more.length)
      ..setAll(0, rest)
      ..setAll(rest.length, more);
    _buf = next;
    _pos = 0;
    if (_buf.length < n) throw const _ReadPastEnd();
  }

  ByteData _take(int n) {
    _ensure(n);
    final data = ByteData.sublistView(_buf, _pos, _pos + n);
    _pos += n;
    return data;
  }

  void _skip(int n) {
    if (n < 0) throw const _ReadPastEnd();
    final inBuf = _buf.length - _pos;
    if (n <= inBuf) {
      _pos += n;
      return;
    }
    final target = _raf.positionSync() + (n - inBuf);
    if (target > _raf.lengthSync()) throw const _ReadPastEnd();
    _raf.setPositionSync(target);
    _buf = Uint8List(0);
    _pos = 0;
  }

  int u32() => _take(4).getUint32(0, Endian.little);
  int i32() => _take(4).getInt32(0, Endian.little);
  int u64() => _take(8).getUint64(0, Endian.little);

  String ggufString() {
    final len = u64();
    if (len < 0 || len > _maxString) throw const _ReadPastEnd();
    _ensure(len);
    final s = utf8.decode(_buf.sublist(_pos, _pos + len), allowMalformed: true);
    _pos += len;
    return s;
  }

  static const _fixedSize = {
    0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8, //
  };

  void skipGgufValue(int type) {
    final fixed = _fixedSize[type];
    if (fixed != null) {
      _skip(fixed);
      return;
    }
    if (type == 8) {
      final len = u64();
      _skip(len);
      return;
    }
    if (type == 9) {
      final itemType = u32();
      final count = u64();
      if (count < 0) throw const _ReadPastEnd();
      final itemFixed = _fixedSize[itemType];
      if (itemFixed != null) {
        _skip(itemFixed * count);
        return;
      }
      for (var i = 0; i < count; i++) {
        skipGgufValue(itemType);
      }
      return;
    }
    throw const FormatException('unknown GGUF value type');
  }
}
