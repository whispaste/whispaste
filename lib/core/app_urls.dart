/// Centralized external URLs — single source of truth for WhisPaste's public
/// web and store destinations.
///
/// Every review / CTA surface that links out to the GitHub repository or a
/// store review entry must read its value from here, so a single edit
/// propagates to all surfaces (the overview ask card and "Mitmachen" block,
/// About page, whisper-server manifest failover).
library;

/// Public API of the project (the social numbers and the newsletter sign-up
/// of the "Mitmachen" block). A preview build points it at staging with
/// `--dart-define=WP_API_BASE_URL=https://…` (no trailing slash); release
/// builds never set it and talk to production.
const String kApiBaseUrl = String.fromEnvironment(
  'WP_API_BASE_URL',
  defaultValue: 'https://api.whispaste.de',
);

/// Live GitHub stars and YouTube subscribers: the one request the app makes for them.
const String kSocialStatsUrl = '$kApiBaseUrl/v1/public/social-stats';

/// Newsletter sign-up (double opt-in) from the "Mitmachen" block.
const String kNewsletterSubscribeUrl = '$kApiBaseUrl/v1/newsletter/subscribe';

/// Whether a pending newsletter sign-up was confirmed (asked only while one
/// is pending, see newsletter_logic.dart).
const String kNewsletterStatusUrl = '$kApiBaseUrl/v1/newsletter/status';

/// WhisPaste GitHub repository home.
const String kGitHubRepoUrl = 'https://github.com/whispaste/whispaste';

/// WhisPaste public website — canonical domain (matches the site's
/// `astro.config.ts` `site`). Note: this is `.de`, not `.com`.
const String kWebsiteUrl = 'https://whispaste.de';

/// WhisPaste changelog on the public website. Used by the About page's
/// "What's new" quick action.
const String kChangelogUrl = '$kWebsiteUrl/changelog';

/// RSS feed of the WhisPaste blog, the source suggested for the "Neuigkeiten"
/// block of the Übersicht. The blog exists in German and English only: German
/// UI maps to the German feed, every other UI language to the English one.
String blogFeedUrl(String languageCode) => languageCode == 'de'
    ? '$kWebsiteUrl/blog/feed.xml'
    : '$kWebsiteUrl/en/blog/feed.xml';

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

/// Website languages with their own `/<lang>/privacy/` page; German has
/// `/datenschutz/`, every other language falls back to English.
const Set<String> _kPrefixedPrivacyLanguages = {
  'es',
  'pt',
  'it',
  'ru',
  'zh',
  'fr',
};

/// The newsletter section (`#newsletter`) of the privacy policy in the app's
/// [languageCode], for the sign-up in the "Mitmachen" block.
String newsletterPrivacyUrl(String languageCode) {
  final page = switch (languageCode) {
    'de' => '/datenschutz/',
    _ when _kPrefixedPrivacyLanguages.contains(languageCode) =>
      '/$languageCode/privacy/',
    _ => '/en/privacy/',
  };
  return '$kWebsiteUrl$page#newsletter';
}

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
    'https://apps.apple.com/app/id6795319409?action=write-review';

/// Microsoft Store product page (listing, not a review sheet). Used by the
/// support page's store card and as the share target of store builds.
const String kMicrosoftStoreListingUrl =
    'https://apps.microsoft.com/detail/9P22JVKRQ2V0';

/// Mac App Store product page. Used by the support page's store card and as
/// the share target of Mac App Store builds.
const String kMacAppStoreListingUrl = 'https://apps.apple.com/app/id6795319409';

/// The team's contact address. Shown on Help › Feedback & contact and used for
/// consent withdrawals by e-mail.
const String kContactEmail = 'kontakt@whispaste.de';

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
