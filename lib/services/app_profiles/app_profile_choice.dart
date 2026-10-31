/// The manual profile choice from the tray (ticket 13, part 2).
///
/// The choice is the same [ProfileChoice] the resolver already honours: a
/// profile forces it, "no profile" beats the rules, and automatic hands the
/// decision back to the per-app rules. It survives an app restart, so a
/// profile picked for a session stays in effect until it is changed again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import 'app_profile_resolver.dart';

const _keyProfileChoice = 'app_profile_choice';
final _log = AppLogger('ProfileChoice');
const _valueAutomatic = 'automatic';
const _valueNone = 'none';
const _valueProfilePrefix = 'profile:';

/// The stored form of [choice]: `automatic`, `none` or `profile:<id>`.
String encodeProfileChoice(ProfileChoice choice) => switch (choice) {
  ProfileChoiceAutomatic() => _valueAutomatic,
  ProfileChoiceNone() => _valueNone,
  ProfileChoiceProfile(:final profileId) => '$_valueProfilePrefix$profileId',
};

/// Reads a stored choice. Anything unknown means automatic, the safe default.
ProfileChoice decodeProfileChoice(String? stored) {
  if (stored == _valueNone) return const ProfileChoiceNone();
  if (stored != null && stored.startsWith(_valueProfilePrefix)) {
    final id = stored.substring(_valueProfilePrefix.length);
    if (id.isNotEmpty) return ProfileChoiceProfile(id);
  }
  return const ProfileChoiceAutomatic();
}

/// Holds the active [ProfileChoice] and keeps it across restarts.
class ProfileChoiceController extends Notifier<ProfileChoice> {
  @override
  ProfileChoice build() {
    _restore();
    return const ProfileChoiceAutomatic();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = decodeProfileChoice(prefs.getString(_keyProfileChoice));
      if (encodeProfileChoice(stored) != encodeProfileChoice(state)) {
        state = stored;
      }
    } on Object catch (e) {
      _log.warning('Profile choice not restored, starting automatic: $e');
    }
  }

  /// Makes [next] the active choice. Returns false, and changes nothing, when
  /// it is already active, so a repeated pick neither repeats the toast nor
  /// writes the preferences again.
  bool select(ProfileChoice next) {
    if (encodeProfileChoice(next) == encodeProfileChoice(state)) return false;
    state = next;
    _persist(next);
    return true;
  }

  Future<void> _persist(ProfileChoice choice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyProfileChoice, encodeProfileChoice(choice));
    } on Object catch (e) {
      _log.warning('Profile choice not saved, it lasts this session only: $e');
    }
  }
}

final profileChoiceProvider =
    NotifierProvider<ProfileChoiceController, ProfileChoice>(
      ProfileChoiceController.new,
    );

/// The overlay chip text for a profile name: trimmed, and shortened so a long
/// name cannot push the chip over the pill's edges. Null for a blank name.
String? profileChipLabelFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  const maxLength = 14;
  if (trimmed.length <= maxLength) return trimmed;
  return '${trimmed.substring(0, maxLength - 1)}…';
}

/// A profile choice that just took effect, for the toast in the app shell.
/// [profileName] is set only for a named profile; the shell words the
/// automatic and no-profile choices itself, in the app's language.
class ProfileSwitchFeedback {
  const ProfileSwitchFeedback({
    required this.choice,
    required this.serial,
    this.profileName,
  });

  final ProfileChoice choice;
  final String? profileName;

  /// Increases on every announcement, so the same choice shows again.
  final int serial;
}

class ProfileSwitchFeedbackController extends Notifier<ProfileSwitchFeedback?> {
  @override
  ProfileSwitchFeedback? build() => null;

  void announce({required ProfileChoice choice, String? profileName}) {
    state = ProfileSwitchFeedback(
      choice: choice,
      profileName: profileName,
      serial: (state?.serial ?? 0) + 1,
    );
  }
}

final profileSwitchFeedbackProvider =
    NotifierProvider<ProfileSwitchFeedbackController, ProfileSwitchFeedback?>(
      ProfileSwitchFeedbackController.new,
    );
