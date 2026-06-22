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
  // Buffered deep link captured before Flutter is ready (cold start case).
  private var _pendingDeepLink: String?
  private var _deepLinkChannel: FlutterMethodChannel?

  // Opaque overlay shown while the app is inactive/backgrounded so financial
  // data isn't visible in the iOS App Switcher snapshot.
  private var _privacyView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Capture widget/live activity URL from cold launch before plugins register
    if let url = launchOptions?[UIApplication.LaunchOptionsKey.url] as? URL,
       url.scheme == "trackora", url.host != "import-receipt" {
      _pendingDeepLink = url.absoluteString
    }
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
    installDeepLinkChannel(messenger: nsMessenger)
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

  private func installDeepLinkChannel(messenger: NSObject & FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "trackora/initial_link", binaryMessenger: messenger)
    _deepLinkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getInitialLink" {
        result(self?._pendingDeepLink)
        self?._pendingDeepLink = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
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
    // Store the URL for Dart to consume on startup or live delivery
    if url.scheme == "trackora" {
      _pendingDeepLink = url.absoluteString
      _deepLinkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
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

  // MARK: - App Switcher privacy

  // Cover the UI before iOS snapshots it for the App Switcher, and reveal it
  // again once the app is active. This keeps balances and transactions out of
  // the background preview.
  override func applicationWillResignActive(_ application: UIApplication) {
    showPrivacyScreen()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    hidePrivacyScreen()
    super.applicationDidBecomeActive(application)
  }

  private func privacyWindow() -> UIWindow? {
    if let w = window { return w }
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    if let key = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
      return key
    }
    return scenes.flatMap { $0.windows }.first
  }

  private func showPrivacyScreen() {
    guard _privacyView == nil, let window = privacyWindow() else { return }

    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Opaque so nothing underneath shows through in the snapshot.
    cover.backgroundColor = UIColor.systemBackground

    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = cover.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.addSubview(blur)

    let label = UILabel()
    label.text = "Trackora"
    label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
    label.textColor = UIColor.label
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])

    window.addSubview(cover)
    _privacyView = cover
  }

  private func hidePrivacyScreen() {
    guard let cover = _privacyView else { return }
    _privacyView = nil
    UIView.animate(
      withDuration: 0.2,
      animations: { cover.alpha = 0 },
      completion: { _ in cover.removeFromSuperview() }
    )
  }
}
