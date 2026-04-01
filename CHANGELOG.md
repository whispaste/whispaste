# Changelog

## 1.1.3.0

A polished UI update that makes WhisPaste feel faster, clearer, and more intuitive to use.

### Highlights

- Redesigned dashboard, Smart Mode, and Voice Snippets screens with cleaner cards and better spacing.
- Smart Mode and Voice Snippets now have separate AI provider settings — choose local or cloud independently.
- Silence removal is now a single, unified setting combining voice detection and trim in one step.
- Page transitions are now smooth and animated for a more premium feel.
- Auto-generated tags now use Title Case and block system tags from leaking into your entries.

### UI and copy improvements

- Settings reorganized into clearer sections with more descriptive labels.
- Replaced jargon like "Transcription" and "Diktat" with everyday language throughout.
- All German translations reviewed and aligned with the current English copy.
- Contextual tips explain features where you need them, not just in onboarding.

### Reliability

- Fixed a race condition when switching pages quickly during transitions.
- Version metadata in Windows resources now stays in sync with the release version.
- Silence detection margins tuned to industry best practices (250 ms pre-speech, 350 ms post-speech).

## 1.1.2.0

This release focuses on safer crash reporting, clearer setup flows, and more consistent communication across the app and website.

### Highlights

- Crash reporting now uses a Supabase relay instead of shipping a direct Discord webhook in the app.
- Release builds now require the public crash-relay URL, so packaged builds keep crash delivery working reliably.
- The onboarding try-dictation flow no longer marks onboarding complete too early while transcription is still finishing.

### Privacy and security

- Public builds ship only the relay URL. Private secrets stay server-side in Supabase.
- Crash-message sanitization is stricter for API keys, bearer tokens, and similar secrets.
- Setup docs now clearly explain which Supabase values are public and which must never be committed.

### Product and copy updates

- Website copy now reflects the real product setup more accurately: local transcription or the cloud provider you choose.
- Privacy messaging now explains optional crash reporting more transparently.
- Download and release messaging no longer implies an OpenAI-only setup.

### Reliability

- Release workflow validation now fails early if the crash-relay configuration is missing or malformed.
- Build metadata stays aligned with the release version more consistently.
