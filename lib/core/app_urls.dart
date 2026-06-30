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

/// WhisPaste public website — canonical domain (matches the site's
/// `astro.config.ts` `site`). Note: this is `.de`, not `.com`.
const String kWebsiteUrl = 'https://whispaste.de';

/// Language-aware home URL of the public website. German UI maps to the
/// default site root; every other UI language maps to the `/en/` site.
String websiteHomeUrl(String languageCode) =>
    languageCode == 'de' ? '$kWebsiteUrl/' : '$kWebsiteUrl/en/';

/// Language-aware privacy-policy URL on the public website. German UI maps to
/// `/datenschutz/`; every other UI language maps to the English `/en/privacy/`
/// policy (the site has no localized legal pages beyond DE/EN).
String privacyPolicyUrl(String languageCode) => languageCode == 'de'
    ? '$kWebsiteUrl/datenschutz/'
    : '$kWebsiteUrl/en/privacy/';

/// Microsoft Store review deep-link. Opens the Windows Store rating sheet
/// directly for the WhisPaste listing. The `ProductId` is the fixed store
/// entry and must not be edited without a store-listing change.
const String kWindowsStoreReviewUrl =
    'ms-windows-store://review/?ProductId=9p22jvkrq2v0';
