/// The kind of feedback a user sends (FB-02/FB-03).
///
/// The form offers four types. The server stores one of four categories
/// (`user_feedback.category`, CHECK `bug|feature|general|ai`), so the mapping
/// below is the only place that decides which category a type lands in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the user is writing about. Chosen as a chip in step one of the form.
enum FeedbackType { problem, idea, praise, question }

/// The server category a [FeedbackType] is stored under.
///
/// Praise and question share `general`: the server has no value for either,
/// and `ai` means "AI quality" in the analytics, so a question must not land
/// there. Adding `praise`/`question` needs a migration first.
String feedbackCategoryFor(FeedbackType type) => switch (type) {
  FeedbackType.problem => 'bug',
  FeedbackType.idea => 'feature',
  FeedbackType.praise => 'general',
  FeedbackType.question => 'general',
};

/// A type chosen by the entry point that opened the form, such as "Idee
/// vorschlagen…". The form takes it once and clears it, so the next plain
/// open starts without a preselection.
final feedbackPresetTypeProvider =
    NotifierProvider<FeedbackPresetTypeNotifier, FeedbackType?>(
      FeedbackPresetTypeNotifier.new,
    );

class FeedbackPresetTypeNotifier extends Notifier<FeedbackType?> {
  @override
  FeedbackType? build() => null;

  void set(FeedbackType? type) => state = type;
}
