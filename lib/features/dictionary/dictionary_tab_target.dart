/// Which Dictionary tab is open, and requests to open one from elsewhere.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tabs of the Dictionary page, in the order they are shown.
enum DictionaryTab { terms, replacements, suggestions }

/// The tab a jump from elsewhere (settings search, a banner action) wants
/// open. `DictionaryPage` takes it once and clears it.
class DictionaryTabTargetNotifier extends Notifier<DictionaryTab?> {
  @override
  DictionaryTab? build() => null;

  void set(DictionaryTab? tab) => state = tab;
}

final dictionaryTabTargetProvider =
    NotifierProvider<DictionaryTabTargetNotifier, DictionaryTab?>(
      DictionaryTabTargetNotifier.new,
    );

/// Set together with the replacements tab: the page opens its "new
/// replacement" dialog once the tab is shown (the terms banner action).
class DictionaryNewReplacementRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final dictionaryNewReplacementRequestProvider =
    NotifierProvider<DictionaryNewReplacementRequest, bool>(
      DictionaryNewReplacementRequest.new,
    );
