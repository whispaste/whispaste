/// Centralized external URLs — single source of truth for WhisPaste's public
/// web and store destinations.
///
/// Every review / CTA surface that links out to the GitHub repository or the
/// Microsoft Store review entry must read its value from here, so a single
/// edit propagates to all surfaces (review-prompt dialog, About page,
/// whisper-server manifest failover, and the follow-up CTA slices).
library;

/// WhisPaste GitHub repository home.
/// Public API of the project (the social numbers of the "Mitmachen" block).
const String kApiBaseUrl = 'https://api.whispaste.de';

/// Live GitHub stars and YouTube subscribers: the one request the app makes for them.
const String kSocialStatsUrl = '$kApiBaseUrl/v1/public/social-stats';

const String kGitHubRepoUrl = 'https://github.com/whispaste/whispaste';

/// WhisPaste public website — canonical domain (matches the site's
/// `astro.config.ts` `site`). Note: this is `.de`, not `.com`.
const String kWebsiteUrl = 'https://whispaste.de';

/// WhisPaste changelog on the public website. Used by the About page's
/// "What's new" quick action.
const String kChangelogUrl = '$kWebsiteUrl/changelog';

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

/// Language-aware legal notice (Impressum) URL on the public website. Same
/// mapping as [privacyPolicyUrl]: German UI to `/impressum/`, every other UI
/// language to the English `/en/impressum/` page.
String imprintUrl(String languageCode) => languageCode == 'de'
    ? '$kWebsiteUrl/impressum/'
    : '$kWebsiteUrl/en/impressum/';

/// Microsoft Store review deep-link. Opens the Windows Store rating sheet
/// directly for the WhisPaste listing. The `ProductId` is the fixed store
/// entry and must not be edited without a store-listing change.
const String kWindowsStoreReviewUrl =
    'ms-windows-store://review/?ProductId=9p22jvkrq2v0';

/// Mac App Store review deep-link. Opens the "Write a Review" sheet directly
/// for the WhisPaste listing. The app id (`6795319409`) is the fixed store
/// entry — same id the website's `MAC_APP_STORE_URL` uses
/// (`website/src/data/platforms.ts`) — and must not be edited without a
/// store-listing change.
const String kMacAppStoreReviewUrl =
    'macappstore://apps.apple.com/app/id6795319409?action=write-review';

/// Microsoft Store product page (listing, not a review sheet). Used by the
/// support page's store card and as the share target of store builds.
const String kMicrosoftStoreListingUrl =
    'https://apps.microsoft.com/detail/9P22JVKRQ2V0';

/// Mac App Store product page. Used by the support page's store card and as
/// the share target of Mac App Store builds.
const String kMacAppStoreListingUrl = 'https://apps.apple.com/app/id6795319409';

/// GitHub Sponsors page for the maintainer. Used by the About page's support
/// section.
const String kGitHubSponsorsUrl = 'https://github.com/sponsors/silvio-l';

/// Ko-fi support page for the maintainer. Used by the About page's support
/// section.
const String kKofiUrl = 'https://ko-fi.com/silviol';

/// Buy Me a Coffee page for the maintainer. Adds the second coffee link next
/// to Ko-fi on direct builds only; store builds never show external links.
const String kBuyMeACoffeeUrl = 'https://buymeacoffee.com/silvio.lindstedt';

/// PayPal one-time support link (extra button next to Ko-fi, direct builds
/// only).
const String kPayPalUrl =
    'https://www.paypal.com/donate/?hosted_button_id=GY8ZQQGJB9XPY';

/// Maintainer's X (Twitter) profile. Used by the About page's links section
/// and the public website's footer.
const String kMaintainerXUrl = 'https://x.com/silviolindstedt';

/// Maintainer's personal GitHub profile. Shown under "From the developer" on
/// the Übersicht only; the project repository stays [kGitHubRepoUrl].
const String kMaintainerGitHubUrl = 'https://github.com/silvio-l';

/// WhisPaste's YouTube channel (videos). Used by the Übersicht's "Get
/// involved" section on every build.
const String kYouTubeChannelUrl = 'https://www.youtube.com/@whispaste';

/// Public Votepit ideas & voting board. Used by the feedback page's
/// thank-you view and the settings review/support section.
const String kVotepitBoardUrl =
    'https://app.votepit.com/silvio-und-maik/whispaste';
