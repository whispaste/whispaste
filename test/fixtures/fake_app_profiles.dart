/// In-memory stand-ins for the profile list and the model download state, so
/// widget and provider tests run without the database or the network. Every
/// write is recorded and also applied to the list, as the real repository does.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/model_download_service.dart';

class FakeAppProfiles extends AppProfilesController {
  FakeAppProfiles(this.initial);

  final List<AppProfile> initial;
  final List<AppProfile> saves = [];
  final List<String> deletes = [];
  final List<List<String>> reorders = [];

  @override
  Future<List<AppProfile>> build() async => initial;

  List<AppProfile> get _current => state.value ?? initial;

  @override
  Future<void> save(AppProfile profile) async {
    saves.add(profile);
    final index = _current.indexWhere((p) => p.id == profile.id);
    final next = [..._current];
    if (index < 0) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = AsyncData(next);
  }

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
    state = AsyncData([
      for (final p in _current)
        if (p.id != id) p,
    ]);
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    reorders.add(orderedIds);
    final byId = {for (final p in _current) p.id: p};
    state = AsyncData([for (final id in orderedIds) byId[id]!]);
  }
}

/// Settings without touching preferences or the database.
class FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(hotkeyEnabled: false);
}

/// No downloaded speech models.
class FakeModelDownloads extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}
