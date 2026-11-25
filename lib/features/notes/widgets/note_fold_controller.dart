/// The page's handle on folding in the long-note editor (#1344): the editor
/// menu folds or unfolds all sections through it and shows those entries
/// only while the open note has a section to fold.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the long-note editor offers to the page.
abstract interface class NoteFoldTarget {
  bool get hasFoldableSections;
  bool get hasFoldedSections;
  void foldAllSections();
  void unfoldAllSections();
}

class NoteFoldController extends ChangeNotifier {
  NoteFoldTarget? _target;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Whether the open note has a section that can be folded.
  bool get canFold => _target?.hasFoldableSections ?? false;

  /// Whether any section is folded right now.
  bool get anyFolded => _target?.hasFoldedSections ?? false;

  void foldAll() => _target?.foldAllSections();

  void unfoldAll() => _target?.unfoldAllSections();

  /// The editor registers itself while it is mounted.
  void attach(NoteFoldTarget target) {
    _target = target;
    changed();
  }

  void detach(NoteFoldTarget target) {
    if (!identical(_target, target)) return;
    _target = null;
    changed();
  }

  /// Sections or folds changed. Listeners hear it after the frame: the
  /// editor reports from its own build and layout, where the menu must not
  /// rebuild.
  void changed() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
