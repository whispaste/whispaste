/// How this Linux build was installed. Decides which auto-paste hint the
/// onboarding shows: the sandboxes need a manual step, native packages do not.
enum LinuxPackageFormat {
  /// `.deb` or any native install: uinput works without an extra step.
  native,

  /// Flatpak: works with the `--device=all` finish-arg in the manifest.
  flatpak,

  /// Snap: the `uinput` interface must be connected once by the user.
  snap,

  /// AppImage: needs the udev rule or the `input` group for `/dev/uinput`.
  appimage,
}

/// Detects the package format of the running process. Pure function: every
/// fact is injected so the detection is testable without a real sandbox.
///
/// The env variables alone are not enough: `SNAP` and `APPIMAGE` are inherited
/// by child processes, so a native binary started from inside a snap or an
/// AppImage would look packaged. Each format is therefore confirmed by a fact
/// that only that runtime sets for the process itself:
/// - Flatpak: `/.flatpak-info` exists ([flatpakInfoPresent]).
/// - Snap: [executable] lives under the `SNAP` mount point.
/// - AppImage: `APPIMAGE` names a file that exists ([appImageFilePresent]),
///   `APPDIR` is set and [executable] lies under `APPDIR`.
LinuxPackageFormat linuxPackageFormatFrom({
  required Map<String, String> env,
  required String executable,
  required bool flatpakInfoPresent,
  required bool appImageFilePresent,
}) {
  String value(String key) => env[key] ?? '';
  if (flatpakInfoPresent) return LinuxPackageFormat.flatpak;
  final snapMount = value('SNAP');
  if (snapMount.isNotEmpty && executable.startsWith('$snapMount/')) {
    return LinuxPackageFormat.snap;
  }
  // A trailing slash would make the prefix check below look for `//`.
  final appDir = value('APPDIR').replaceAll(RegExp(r'/+$'), '');
  if (value('APPIMAGE').isNotEmpty &&
      appImageFilePresent &&
      appDir.isNotEmpty &&
      executable.startsWith('$appDir/')) {
    return LinuxPackageFormat.appimage;
  }
  return LinuxPackageFormat.native;
}
