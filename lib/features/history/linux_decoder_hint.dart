/// Which install hint a missing GStreamer AAC decoder gets on Linux. The
/// package format decides what the user can do: apt works for the .deb and
/// the tarball, the Flatpak and Snap sandboxes need their own path (PAR-040).
enum LinuxDecoderHint { apt, flatpak, snap }

/// Pure decision from the process environment. Flatpak sets `FLATPAK_ID`,
/// Snap sets `SNAP` or `SNAP_NAME`. Anything else is a native install.
LinuxDecoderHint linuxDecoderHintFrom(Map<String, String> env) {
  if ((env['FLATPAK_ID'] ?? '').isNotEmpty) return LinuxDecoderHint.flatpak;
  if (env.containsKey('SNAP') || env.containsKey('SNAP_NAME')) {
    return LinuxDecoderHint.snap;
  }
  return LinuxDecoderHint.apt;
}
