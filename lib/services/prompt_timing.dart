/// Shared timing policy for post-recording nudge dialogs (review prompt,
/// support prompt).
///
/// A recording's completion is a high-focus moment — the user just triggered
/// paste/copy of their transcript. Interrupting immediately reads as jarring.
/// This delay is deliberately longer than a "just happened" instant so a
/// nudge dialog never feels like it fired in direct reaction to finishing a
/// transcription.
library;

/// Minimum time a nudge dialog (review or support prompt) must wait after a
/// recording completes before it is allowed to appear.
///
/// Kept as a single named constant so [isPromptDelayElapsed] and every
/// prompt watcher (`WpReviewPromptWatcher`, `WpSupportPromptWatcher`) stay in
/// sync — this is intentionally 5 seconds, materially longer than the 1
/// second a user needs to notice their pasted text landed.
const Duration kPostRecordingPromptDelay = Duration(seconds: 5);

/// Pure decision function: has enough time elapsed since a recording
/// completed for a nudge dialog to be shown without feeling like an
/// interruption of the completion moment itself?
///
/// Returns `false` for any [elapsedSinceCompletion] shorter than
/// [kPostRecordingPromptDelay] — in particular for the previous 1-second
/// timing this project used, which read as too close to completion.
bool isPromptDelayElapsed(Duration elapsedSinceCompletion) =>
    elapsedSinceCompletion >= kPostRecordingPromptDelay;
