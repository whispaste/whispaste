import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;

Future<void>? _appFonts;

/// Loads the real app fonts once per test isolate (#1570).
///
/// Every `loadAppFonts` call registers all font families again and keeps
/// about 650 MB the isolate never frees. The lab lanes run up to 15 test files
/// in one isolate (tool/test_bundles.dart), so six onboarding files that each
/// loaded the fonts in `setUpAll` grew one test process to 4.6 GB, filled the
/// 6 GB ubu guest and its swap, and the next font load ran past the time
/// limit (lab run 9644: 107 failures in one bundle). Loaded fonts stay
/// registered for the whole isolate, so one load serves every later file.
Future<void> loadAppFontsOnce() => _appFonts ??= loadAppFonts();
