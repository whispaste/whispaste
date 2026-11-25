/// `user_models.json`: the list of models the user added themselves (#1789),
/// apart from the catalog. Also holds the hosts they confirmed and the
/// catalog choice to fall back to.
///
/// Lives in [userModelsDir] next to one folder per model. Written whole and
/// atomically (temp file, then rename), so a crash never leaves half a list.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../path_service.dart' show userModelsDir;
import 'user_model.dart';

final _log = AppLogger('UserModelStore');

/// Names of the user's own models by id, as last read or written. Lets
/// history and the overview name an own model without reading the file per
/// row (`displayNameForModel`).
final Map<String, String> knownUserModelNames = {};

UserModelsData _remember(UserModelsData data) {
  knownUserModelNames
    ..clear()
    ..addAll({for (final m in data.models) m.id: m.name});
  return data;
}

/// Everything in `user_models.json`.
class UserModelsData {
  const UserModelsData({
    this.models = const [],
    this.confirmedHosts = const {},
    this.speechFallback,
    this.hfSearchConsent = false,
  });

  final List<UserModel> models;

  /// Whether the user agreed that the model library may search
  /// huggingface.co (#2047). Off until they agree in the "+" dialog;
  /// revocable in the privacy settings.
  final bool hfSearchConsent;

  /// Hosts outside the fixed allowlist the user confirmed, lower case.
  final Set<String> confirmedHosts;

  /// The catalog speech choice in use before the user switched to a model of
  /// their own; restored when that model fails.
  final SpeechFallbackChoice? speechFallback;

  UserModel? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  UserModelsData copyWith({
    List<UserModel>? models,
    Set<String>? confirmedHosts,
    SpeechFallbackChoice? speechFallback,
    bool? hfSearchConsent,
  }) => UserModelsData(
    models: models ?? this.models,
    confirmedHosts: confirmedHosts ?? this.confirmedHosts,
    speechFallback: speechFallback ?? this.speechFallback,
    hfSearchConsent: hfSearchConsent ?? this.hfSearchConsent,
  );

  /// [models] with [model] replacing the entry of the same id, or appended.
  UserModelsData upsert(UserModel model) {
    final list = [...models];
    final i = list.indexWhere((m) => m.id == model.id);
    if (i < 0) {
      list.add(model);
    } else {
      list[i] = model;
    }
    return copyWith(models: list);
  }

  UserModelsData remove(String id) =>
      copyWith(models: models.where((m) => m.id != id).toList());

  Map<String, Object?> toJson() => {
    'version': 1,
    'models': [for (final m in models) m.toJson()],
    'confirmed_hosts': (confirmedHosts.toList()..sort()),
    'speech_fallback': ?speechFallback?.toJson(),
    if (hfSearchConsent) 'hf_search_consent': true,
  };

  static UserModelsData fromJson(Object? json) {
    if (json is! Map) return const UserModelsData();
    final models = <UserModel>[];
    final raw = json['models'];
    if (raw is List) {
      for (final entry in raw) {
        final model = UserModel.fromJson(entry);
        if (model != null) models.add(model);
      }
    }
    final hosts = json['confirmed_hosts'];
    return UserModelsData(
      models: models,
      confirmedHosts: {
        if (hosts is List)
          for (final h in hosts)
            if (h is String && h.isNotEmpty) h.toLowerCase(),
      },
      speechFallback: SpeechFallbackChoice.fromJson(json['speech_fallback']),
      hfSearchConsent: json['hf_search_consent'] == true,
    );
  }
}

/// Reads and writes `user_models.json` under [root].
class UserModelStore {
  UserModelStore({this._root});

  final String? _root;

  String get root => _root ?? userModelsDir();

  File get _file => File(p.join(root, 'user_models.json'));

  /// The folder of model [id].
  String modelDir(String id) => p.join(root, id);

  /// The list, or an empty one when the file is missing or unreadable (an
  /// unreadable file is kept aside, never overwritten silently).
  UserModelsData readSync() {
    final file = _file;
    if (!file.existsSync()) return const UserModelsData();
    try {
      return _remember(
        UserModelsData.fromJson(jsonDecode(file.readAsStringSync())),
      );
    } on Object catch (e) {
      _log.warning('user_models.json unreadable, keeping it aside: $e');
      try {
        file.renameSync('${file.path}.damaged');
      } on FileSystemException catch (e) {
        // Nothing more to do; the next write replaces it.
        _log.debug('Damaged user_models.json not set aside', e);
      }
      return const UserModelsData();
    }
  }

  void writeSync(UserModelsData data) {
    _remember(data);
    Directory(root).createSync(recursive: true);
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
      flush: true,
    );
    tmp.renameSync(_file.path);
  }

  /// Deletes the folder of model [id]. Never throws.
  void deleteModelFiles(String id) {
    final dir = Directory(modelDir(id));
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      _log.warning('Could not delete the files of $id: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Crash marker
  // -------------------------------------------------------------------------

  File get _marker => File(p.join(root, 'in_flight.json'));

  /// Notes that native code is about to run model [id] inside this process.
  /// If the process dies there, the next start finds the note
  /// ([takeCrashedModelId]) and takes the model out of use.
  void markInFlight(String id) {
    try {
      Directory(root).createSync(recursive: true);
      _marker.writeAsStringSync(jsonEncode({'id': id}), flush: true);
    } on FileSystemException catch (e) {
      _log.warning('Could not write the crash marker: $e');
    }
  }

  /// Clears the note of [markInFlight].
  void clearInFlight() {
    try {
      if (_marker.existsSync()) _marker.deleteSync();
    } on FileSystemException catch (e) {
      _log.warning('Could not clear the crash marker: $e');
    }
  }

  /// The model a previous run died in, once; clears the note.
  String? takeCrashedModelId() {
    final marker = _marker;
    if (!marker.existsSync()) return null;
    String? id;
    try {
      final json = jsonDecode(marker.readAsStringSync());
      if (json is Map && json['id'] is String) id = json['id'] as String;
    } on Object {
      id = null;
    }
    clearInFlight();
    return id;
  }
}
