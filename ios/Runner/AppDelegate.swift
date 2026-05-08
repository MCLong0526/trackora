import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // WCSession.delegate is a weak reference. Without a strong owner here the
  // WatchUserInfoBridge would be deallocated immediately after installation,
  // leaving session.delegate == nil and causing WCErrorCodeSessionMissingDelegate.
  private var _watchBridge: WatchUserInfoBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // FlutterImplicitEngineBridge exposes applicationRegistrar (not binaryMessenger).
    // Cast to NSObject so FlutterMethodChannel accepts it.
    let messenger = engineBridge.applicationRegistrar.messenger()
    guard let nsMessenger = messenger as? NSObject & FlutterBinaryMessenger else {
      print("[PHONE_SYNC] WatchUserInfoBridge: could not cast messenger — skipping")
      return
    }
    installWatchUserInfoBridge(messenger: nsMessenger)
  }

  /// Wraps the watch_connectivity plugin's WCSession delegate to add
  /// didReceiveUserInfo support for Watch→Phone transferUserInfo delivery.
  private func installWatchUserInfoBridge(messenger: NSObject & FlutterBinaryMessenger) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard let original = session.delegate else {
      print("[PHONE_SYNC] WatchUserInfoBridge: no existing delegate found — skipping")
      return
    }
    let channel = FlutterMethodChannel(
      name: "trackora/watch_queue",
      binaryMessenger: messenger
    )
    let bridge = WatchUserInfoBridge(wrapping: original, channel: channel)
    _watchBridge = bridge          // Strong retain — keeps bridge alive for the app lifetime
    session.delegate = bridge      // WCSession.delegate is weak; _watchBridge prevents dealloc
    // Ensure activation if the plugin registered lazily (idempotent when activating).
    if session.activationState == .notActivated {
      session.activate()
    }
    print("[PHONE_SYNC] WatchUserInfoBridge installed over \(type(of: original))")
  }
}
