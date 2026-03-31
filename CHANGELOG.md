# Changelog

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
