import 'package:flutter/material.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

/// Custom screenshot device definitions for WhisPaste store listings.
///
/// Microsoft Store requires: 1366×768 minimum, up to 3840×2160.
/// We generate at 1366×768 (1× for standard) and 2732×1536 (2× for HiDPI).
enum WpScreenshotDevices {
  /// Standard Microsoft Store resolution (1366×768).
  windowsStore(
    ScreenshotDevice(
      platform: TargetPlatform.windows,
      resolution: Size(1366, 768),
      pixelRatio: 1,
      goldenSubFolder: 'windowsStoreScreenshots/',
      frameBuilder: ScreenshotFrame.noFrame,
    ),
  ),

  /// HiDPI variant (2× scale, renders at 2732×1536).
  windowsStoreHiDpi(
    ScreenshotDevice(
      platform: TargetPlatform.windows,
      resolution: Size(2732, 1536),
      pixelRatio: 2,
      goldenSubFolder: 'windowsStoreHiDpiScreenshots/',
      frameBuilder: ScreenshotFrame.noFrame,
    ),
  );

  const WpScreenshotDevices(this.device);
  final ScreenshotDevice device;
}
