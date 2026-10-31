import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Forward the process arguments to Dart's main(): unlike the Windows and
    // Linux runners, the macOS embedder does not do this by default, and
    // `--toggle`/`--cancel` (CLI remote control, see
    // lib/services/single_instance_service.dart) must reach Dart to be
    // forwarded to the running instance.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // A "check automatically" answer from Sparkle's own permission prompt
    // (shown by builds before SUEnableAutomaticChecks=false) is stored in the
    // user defaults and would override Info.plist, letting Sparkle poll the
    // appcast behind the "Check for Updates" toggle. Drop it before the
    // auto_updater plugin starts the updater during registration.
    UserDefaults.standard.removeObject(forKey: "SUEnableAutomaticChecks")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
