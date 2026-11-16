/// Backup forms of the data key (#1166, part of #1157).
///
/// The maintainer decided on two equal ways to back up the data key, both
/// without a password (2026-11-10):
///
/// - a **recovery code** to write down or copy, and
/// - a **backup file** to keep somewhere safe.
///
/// Both carry the very same 32 key bytes. The code is Crockford Base32 of the
/// key plus a 24-bit checksum (the first three bytes of
/// `SHA-256("whispaste-data-key-v1" ‖ key)`), 56 characters in 14 groups of
/// four. A mistyped or swapped character makes the checksum fail instead of
/// yielding a different key; the probability that a random typo passes is
/// 1 in 16.7 million. Crockford's alphabet has no I, L, O or U, and the
/// decoder reads `I`/`L` as `1` and `O` as `0`, ignores case, spaces and
/// dashes, so what was written by hand reads back.
///
/// The file is a small JSON document holding the same recovery code (so it
/// passes the same checksum), the SHA-256 fingerprint the data-key marker
/// keeps, and an English note on what the file is worth.
///
/// ## Secrecy
///
/// Code and file are as valuable as the key itself. Nothing here logs them;
/// [DataKeyBackupError] carries no part of the input, and parsed results
/// redact their `toString`.
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'data_key_store.dart' show dataKeyLength;

/// Crockford Base32 alphabet (no I, L, O, U).
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Domain prefix of the checksum, so a future format can never collide.
const _checksumDomain = 'whispaste-data-key-v1';

/// Checksum length in bytes.
const _checksumLength = 3;

/// Characters per group of the formatted code.
const _groupLength = 4;

/// Length of the code without separators: (32 + 3) bytes = 280 bits.
const dataKeyRecoveryCodeLength =
    ((dataKeyLength + _checksumLength) * 8) ~/ 5; // 56

/// `format` value of a backup file.
const dataKeyBackupFormat = 'whispaste-data-key-backup';

/// Current backup-file version.
const dataKeyBackupVersion = 1;

/// File extension of a backup file (without dot).
const dataKeyBackupExtension = 'wpkey';

/// Suggested name when saving a backup file.
const dataKeyBackupFileName = 'whispaste-data-key.$dataKeyBackupExtension';

/// Why a code or file could not be read. Never names any part of the input.
enum DataKeyBackupError {
  /// Nothing was entered.
  empty,

  /// A character outside the code alphabet.
  invalidCharacter,

  /// Too few or too many characters.
  wrongLength,

  /// All characters valid, but the checksum does not match: a typo.
  checksumMismatch,

  /// The file is not a WhisPaste data-key backup.
  notABackup,

  /// A backup from a newer WhisPaste that this version cannot read.
  unsupportedVersion,
}

/// Result of reading a recovery code or backup file.
sealed class DataKeyBackupParse {
  const DataKeyBackupParse();
}

/// The key bytes behind a valid code or file.
final class DataKeyBackupValid extends DataKeyBackupParse {
  DataKeyBackupValid._(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  /// A copy of the raw key bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// SHA-256 fingerprint, the same value the data-key marker keeps.
  String get fingerprint => sha256.convert(_bytes).toString();

  @override
  String toString() => 'DataKeyBackupValid(<redacted>)';
}

/// The input could not be read; see [error].
final class DataKeyBackupInvalid extends DataKeyBackupParse {
  const DataKeyBackupInvalid(this.error);

  final DataKeyBackupError error;

  @override
  String toString() => 'DataKeyBackupInvalid($error)';
}

List<int> _checksum(List<int> key) => sha256
    .convert([...utf8.encode(_checksumDomain), ...key])
    .bytes
    .sublist(0, _checksumLength);

/// The recovery code of [key] (32 bytes), grouped as `XXXX-XXXX-…`.
String dataKeyRecoveryCode(List<int> key) {
  if (key.length != dataKeyLength) {
    throw ArgumentError('data key must be $dataKeyLength bytes');
  }
  final payload = [...key, ..._checksum(key)];
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  var written = 0;
  for (final byte in payload) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      if (written > 0 && written % _groupLength == 0) out.write('-');
      out.write(_alphabet[(buffer >> bits) & 0x1f]);
      buffer &= (1 << bits) - 1;
      written++;
    }
  }
  return out.toString();
}

/// Value of one code character, tolerant of handwriting, or -1.
int _valueOf(String char) {
  final c = switch (char) {
    'I' || 'L' => '1',
    'O' => '0',
    _ => char,
  };
  return _alphabet.indexOf(c);
}

/// Reads a recovery code as typed or pasted: case, spaces, line breaks and
/// dashes do not matter; `I`/`L` count as `1`, `O` as `0`.
DataKeyBackupParse parseDataKeyRecoveryCode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s\-–—_.]'), '');
  if (cleaned.isEmpty) {
    return const DataKeyBackupInvalid(DataKeyBackupError.empty);
  }
  final values = <int>[];
  for (final char in cleaned.split('')) {
    final value = _valueOf(char);
    if (value < 0) {
      return const DataKeyBackupInvalid(DataKeyBackupError.invalidCharacter);
    }
    values.add(value);
  }
  if (values.length != dataKeyRecoveryCodeLength) {
    return const DataKeyBackupInvalid(DataKeyBackupError.wrongLength);
  }
  final payload = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final value in values) {
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      payload.add((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  final key = payload.sublist(0, dataKeyLength);
  final checksum = payload.sublist(dataKeyLength);
  final expected = _checksum(key);
  for (var i = 0; i < _checksumLength; i++) {
    if (checksum[i] != expected[i]) {
      return const DataKeyBackupInvalid(DataKeyBackupError.checksumMismatch);
    }
  }
  return DataKeyBackupValid._(key);
}

/// Contents of a backup file for [key], created at [createdAt].
String dataKeyBackupFileContents(List<int> key, DateTime createdAt) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({'format': dataKeyBackupFormat, 'version': dataKeyBackupVersion, 'note': 'WhisPaste data key backup. Anyone who has this file and a copy of '
      'your WhisPaste data can read your history and recordings. Keep it '
      'somewhere safe, not next to your data and not unprotected in a '
      'cloud folder.', 'createdAt': createdAt.toUtc().toIso8601String(), 'fingerprint': sha256.convert(key).toString(), 'recoveryCode': dataKeyRecoveryCode(key)})}\n';
}

/// Reads a backup file. The recovery code inside passes the same checksum,
/// and a fingerprint, when present, must match the key.
DataKeyBackupParse parseDataKeyBackupFile(String contents) {
  if (contents.trim().isEmpty) {
    return const DataKeyBackupInvalid(DataKeyBackupError.empty);
  }
  final Object? json;
  try {
    json = jsonDecode(contents);
  } on FormatException {
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  }
  if (json is! Map<String, Object?> || json['format'] != dataKeyBackupFormat) {
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  }
  final version = json['version'];
  if (version is! int) {
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  }
  if (version > dataKeyBackupVersion) {
    return const DataKeyBackupInvalid(DataKeyBackupError.unsupportedVersion);
  }
  final code = json['recoveryCode'];
  if (code is! String) {
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  }
  final parsed = parseDataKeyRecoveryCode(code);
  final fingerprint = json['fingerprint'];
  if (parsed is DataKeyBackupValid &&
      fingerprint is String &&
      fingerprint != parsed.fingerprint) {
    return const DataKeyBackupInvalid(DataKeyBackupError.checksumMismatch);
  }
  return parsed;
}

/// Backup files use owner-only POSIX permissions on the actual host.
bool get dataKeyBackupNeedsPosixPermissions => !Platform.isWindows;
