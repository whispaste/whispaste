/// Centralized external URLs — single source of truth for WhisPaste's public
/// web and store destinations.
///
/// Every review / CTA surface that links out to the GitHub repository or the
/// Microsoft Store review entry must read its value from here, so a single
/// edit propagates to all surfaces (review-prompt dialog, About page,
/// whisper-server manifest failover, and the follow-up CTA slices).
library;

/// WhisPaste GitHub repository home.
const String kGitHubRepoUrl = 'https://github.com/whispaste/whispaste';

/// Microsoft Store review deep-link. Opens the Windows Store rating sheet
/// directly for the WhisPaste listing. The `ProductId` is the fixed store
/// entry and must not be edited without a store-listing change.
const String kWindowsStoreReviewUrl =
    'ms-windows-store://review/?ProductId=9p22jvkrq2v0';
