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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
