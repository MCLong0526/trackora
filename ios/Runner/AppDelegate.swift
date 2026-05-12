import Flutter
import UIKit
import UserNotifications
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // WCSession.delegate is a weak reference. Without a strong owner here the
  // WatchUserInfoBridge would be deallocated immediately after installation,
  // leaving session.delegate == nil and causing WCErrorCodeSessionMissingDelegate.
  private var _watchBridge: WatchUserInfoBridge?
  private var _shareImportService: ShareImportService?
  private var _liveActivityService: LiveActivityService?
  // Buffered trigger: import URL/notification arrived before engine was ready.
  private var _pendingShareImport = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    // Receive notification taps (share import) even when app is in foreground.
    center.delegate = self
    // Request permission so the Share Extension can show local notifications.
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
    installShareImportService(messenger: nsMessenger)
    installLiveActivityService(messenger: nsMessenger)
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

  private func installShareImportService(messenger: NSObject & FlutterBinaryMessenger) {
    _shareImportService = ShareImportService(messenger: messenger)
    print("[SHARE_IMPORT] ShareImportService installed")
    // Flush any URL/notification trigger that arrived before the engine was ready.
    if _pendingShareImport {
      _pendingShareImport = false
      _shareImportService?.notifyShareImport()
    }
  }

  private func installLiveActivityService(messenger: NSObject & FlutterBinaryMessenger) {
    _liveActivityService = LiveActivityService(messenger: messenger)
    print("[LIVE_ACTIVITY] LiveActivityService installed")
  }

  // MARK: - URL scheme (trackora://import-receipt from Share Extension)

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "trackora" && url.host == "import-receipt" {
      triggerShareImport()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  // MARK: - UNUserNotificationCenterDelegate

  // User tapped the "Expense ready to review" notification.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let id = response.notification.request.identifier
    if id.hasPrefix("trackora-share-") {
      triggerShareImport()
    }
    completionHandler()
  }

  // Show the notification banner even when the app is already in the foreground
  // so the user sees the confirmation. The import screen will also open directly,
  // but the banner acts as a visible confirmation.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.identifier.hasPrefix("trackora-share-") {
      // Suppress the banner when the import screen is already opening.
      completionHandler([])
    } else {
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .sound])
      } else {
        completionHandler([.alert, .sound])
      }
    }
  }

  // MARK: - Shared trigger

  private func triggerShareImport() {
    if let service = _shareImportService {
      service.notifyShareImport()
    } else {
      // Engine not ready yet — will flush in installShareImportService.
      _pendingShareImport = true
    }
  }
}
