/// Abstraction over the `launch_at_startup` plugin's static API so
/// [AutostartService] can be tested against a deterministic fake instead of
/// real OS-level registration (Windows registry, macOS login items, Linux
/// autostart entries).
abstract class AutostartBackend {
  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();

  /// macOS: the login item is registered but the user has not approved it in
  /// System Settings yet, so it will not launch until they do.
  Future<bool> requiresApproval();

  /// macOS: opens System Settings at the Login Items pane.
  Future<void> openLoginItems();
}
