import Cocoa
import FlutterMacOS
import HotKey
import Carbon

public class HotkeyManagerMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var _eventSink: FlutterEventSink?
    private var _stampChannel: FlutterMethodChannel?
    
    var hotKeyDict: Dictionary<String, HotKey> = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.leanflutter.plugins/hotkey_manager", binaryMessenger: registrar.messenger)
        let instance = HotkeyManagerMacosPlugin()
        // WhisPaste fork: the event stream of the package carries no time, so
        // the system's own event time goes ahead on this channel (issue #809).
        instance._stampChannel = FlutterMethodChannel(name: "whispaste/hotkey_event_time", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "dev.leanflutter.plugins/hotkey_manager_event", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self._eventSink = events
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self._eventSink = nil
        return nil
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "register":
            register(call, result: result)
            break
        case "unregister":
            unregister(call, result: result)
            break
        case "unregisterAll":
            unregisterAll(call, result: result)
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func register(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args:[String: Any] = call.arguments as! [String: Any]
        
        guard let keyCode = args["keyCode"] as? UInt32 else {
            result(FlutterError(code: "hotkey_unsupported",
                                message: "macOS does not expose a native code for this key.",
                                details: nil))
            return
        }
        let modifiers = args["modifiers"] as! Array<String>
        let identifier = args["identifier"] as! String
        
        guard let key = Key(carbonKeyCode: keyCode) else {
            result(FlutterError(code: "hotkey_unsupported",
                                message: "The key code is not supported.",
                                details: nil))
            return
        }

        // WhisPaste fork: the HotKey pod drops a failed Carbon registration
        // silently, so probe the combination first and report the real result
        // instead of answering true.
        let probeStatus = HotkeyManagerMacosPlugin.probeRegistration(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags.init(pluginModifiers: modifiers))
        if probeStatus != noErr {
            result(FlutterError(code: "hotkey_unavailable",
                                message: "RegisterEventHotKey failed (OSStatus \(probeStatus)).",
                                details: nil))
            return
        }

        let hotKey: HotKey = HotKey(
            key: key,
            modifiers: NSEvent.ModifierFlags.init(pluginModifiers: modifiers)
        )
        hotKey.keyDownHandler = {
            guard let eventSink = self._eventSink else {
                return
            }
            self.sendStamp(type: "onKeyDown", identifier: identifier)
            let event: NSDictionary = [
                "type": "onKeyDown",
                "data": call.arguments as! NSDictionary,
            ]
            eventSink(event)
        }
        hotKey.keyUpHandler = {
            guard let eventSink = self._eventSink else {
                return
            }
            self.sendStamp(type: "onKeyUp", identifier: identifier)
            let event: NSDictionary = [
                "type": "onKeyUp",
                "data": call.arguments as! NSDictionary,
            ]
            eventSink(event)
        }
        self.hotKeyDict[identifier] = hotKey
        result(true)
    }
    
    /// Sends the event time of the Carbon event being dispatched (seconds on the
    /// boot clock, like NSEvent.timestamp) as milliseconds, right before the
    /// event itself: both go the same ordered way to Dart.
    func sendStamp(type: String, identifier: String) {
        let at = GetCurrentEventTime()
        guard at >= 0 else { return }
        _stampChannel?.invokeMethod("stamp", arguments: [
            "type": type,
            "identifier": identifier,
            "atMs": Int((at * 1000).rounded()),
        ])
    }

    /// Registers the combination once with Carbon and releases it again.
    /// Returns the OSStatus of the registration (noErr = free).
    static func probeRegistration(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> OSStatus {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5750_5042), id: 1)  // 'WPPB'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.carbonFlags,
            id,
            GetEventDispatcherTarget(),
            0,
            &ref)
        if status == noErr, let ref = ref {
            UnregisterEventHotKey(ref)
        }
        return status
    }

    public func unregister(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args:[String: Any] = call.arguments as! [String: Any]
        
        let identifier = args["identifier"] as! String
        
        self.hotKeyDict[identifier] = nil;
        
        result(true)
    }
    
    public func unregisterAll(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.hotKeyDict.removeAll();
        result(true)
    }
}
