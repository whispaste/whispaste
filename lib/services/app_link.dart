/// The app's own URL scheme, `whispaste://`. Every desktop channel registers
/// it (Info.plist, MSIX, the Windows runner, the Linux desktop entries; see
/// test/parity/url_scheme_parity_test.dart), so a web page can
/// hand the user back to the app.
///
/// A link is untrusted input from any web page: it carries no data, and the
/// app only acts on the exact paths below. Anything else under the scheme
/// just brings the window to the front.
library;

/// The scheme every channel registers.
const String kAppUrlScheme = 'whispaste';

/// The newsletter confirmation page links here after a confirmation that
/// started in the app.
const String kNewsletterConfirmedLink = '$kAppUrlScheme://newsletter/confirmed';

/// What a launch argument or an opened URL asks of the app.
enum AppLink {
  /// Not a link of this app (a flag, a file, another scheme).
  none,

  /// A `whispaste://` link the app has no action for.
  other,

  /// [kNewsletterConfirmedLink]: show the newsletter status.
  newsletterConfirmed;

  /// Reads one argument. Only the bare path counts as
  /// [newsletterConfirmed]: a query, a fragment, a user or a port make it
  /// [other].
  static AppLink parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.toLowerCase() != kAppUrlScheme) return none;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final bare =
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
    if (bare &&
        uri.host.toLowerCase() == 'newsletter' &&
        path == '/confirmed') {
      return newsletterConfirmed;
    }
    return other;
  }
}
