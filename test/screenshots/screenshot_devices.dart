import 'package:flutter/material.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

/// Custom screenshot device definitions for WhisPaste store listings.
///
/// Microsoft Store requires: 1366×768 minimum, up to 3840×2160.
/// Mac App Store requires: 1280×800 minimum (16:10), up to 2560×1600.
enum WpScreenshotDevices {
  /// Standard Microsoft Store resolution (1920×1080, Windows chrome).
  windowsStore(
    ScreenshotDevice(
      platform: TargetPlatform.windows,
      resolution: Size(1920, 1080),
      pixelRatio: 1,
      goldenSubFolder: 'windowsStoreScreenshots/',
      frameBuilder: ScreenshotFrame.noFrame,
    ),
  ),

  /// Mac App Store (1440×900, 16:10, macOS traffic-light chrome).
  ///
  /// Apple requires at least 1280×800 px; 1440×900 matches the 13"
  /// MacBook Air/Pro screen and sits comfortably within the 2560×1600 max.
  macStore(
    ScreenshotDevice(
      platform: TargetPlatform.macOS,
      resolution: Size(1440, 900),
      pixelRatio: 1,
      goldenSubFolder: 'macStoreScreenshots/',
      frameBuilder: ScreenshotFrame.noFrame,
    ),
  );

  const WpScreenshotDevices(this.device);
  final ScreenshotDevice device;
}
