/// Navigation anchors in the unified dictionary page.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Historical tab identifiers, retained for existing navigation callers.
enum DictionaryTab { replacements, suggestions }

/// The section a jump from elsewhere wants visible. `DictionaryPage`
/// scrolls to it once and clears the request.
class DictionaryTabTargetNotifier extends Notifier<DictionaryTab?> {
  @override
  DictionaryTab? build() => null;

  void set(DictionaryTab? tab) => state = tab;
}

final dictionaryTabTargetProvider =
    NotifierProvider<DictionaryTabTargetNotifier, DictionaryTab?>(
      DictionaryTabTargetNotifier.new,
    );

/// A request to open the replacement editor when entering the dictionary.
class DictionaryNewReplacementRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final dictionaryNewReplacementRequestProvider =
    NotifierProvider<DictionaryNewReplacementRequest, bool>(
      DictionaryNewReplacementRequest.new,
    );
