import UIKit
import UniformTypeIdentifiers
import MobileCoreServices
import UserNotifications
import Vision

/// iOS Share Extension entry point.
///
/// Flow:
/// 1. Receives a shared image from the iOS Share Sheet.
/// 2. Saves it as `pending_share_image.jpg` in the App Group container.
/// 3. Runs Vision OCR on the image and saves raw text to App Group UserDefaults.
/// 4. Schedules a local notification "Receipt scanned" after OCR completes.
/// 5. Tries to open the main app via URL scheme.
/// 6. Closes the extension.
class ShareViewController: UIViewController {

    private let appGroupId   = "group.com.michaelchia.trackora"
    private let imageName    = "pending_share_image.jpg"
    private let timestampKey = "pendingShareTimestamp"
    private let rawTextKey   = "pendingShareRawText"
    private let deepLinkURL  = "trackora://import-receipt"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        extractAndForwardImage()
    }

    // MARK: - Image extraction

    private func extractAndForwardImage() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(success: false); return
        }

        let imageTypes: [String]
        if #available(iOS 14.0, *) {
            imageTypes = [
                UTType.image.identifier,
                UTType.jpeg.identifier,
                UTType.png.identifier,
                UTType.heic.identifier,
            ]
        } else {
            imageTypes = [kUTTypeImage as String, kUTTypeJPEG as String, kUTTypePNG as String]
        }

        for item in items {
            for provider in item.attachments ?? [] {
                for typeId in imageTypes where provider.hasItemConformingToTypeIdentifier(typeId) {
                    provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] data, error in
                        guard let self = self, error == nil else {
                            DispatchQueue.main.async { self?.finish(success: false) }
                            return
                        }
                        self.processLoadedItem(data)
                    }
                    return // handled first match
                }
            }
        }

        finish(success: false)
    }

    private func processLoadedItem(_ item: NSSecureCoding?) {
        var imageData: Data?

        if let url = item as? URL {
            imageData = try? Data(contentsOf: url)
        } else if let img = item as? UIImage {
            imageData = img.jpegData(compressionQuality: 0.85)
        } else if let data = item as? Data {
            imageData = data
        }

        guard let data = imageData else {
            DispatchQueue.main.async { self.finish(success: false) }
            return
        }

        saveToAppGroup(data: data)
    }

    // MARK: - App Group storage

    private func saveToAppGroup(data: Data) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            DispatchQueue.main.async { self.finish(success: false) }
            return
        }

        let imageURL = container.appendingPathComponent(imageName)
        do {
            try data.write(to: imageURL, options: .atomic)
            let defaults = UserDefaults(suiteName: appGroupId)
            defaults?.set(Date().timeIntervalSince1970, forKey: timestampKey)
            // Clear any stale rawText from a previous share.
            defaults?.removeObject(forKey: rawTextKey)
            runOcrAndFinish(imageURL: imageURL)
        } catch {
            DispatchQueue.main.async { self.finish(success: false) }
        }
    }

    // MARK: - OCR (Vision)

    /// Runs Vision text recognition on the saved image, stores the result in
    /// App Group UserDefaults, then schedules the notification and opens the app.
    private func runOcrAndFinish(imageURL: URL) {
        guard let image = UIImage(contentsOfFile: imageURL.path),
              let cgImage = image.cgImage else {
            DispatchQueue.main.async { self.openMainApp(rawText: nil) }
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            var rawText: String? = nil
            if error == nil, let observations = request.results as? [VNRecognizedTextObservation] {
                let joined = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                rawText = joined.isEmpty ? nil : joined
            }
            DispatchQueue.main.async { self?.openMainApp(rawText: rawText) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    // MARK: - Open main app

    private func openMainApp(rawText: String?) {
        // Persist rawText so the main app doesn't need to re-run OCR.
        if let text = rawText {
            UserDefaults(suiteName: appGroupId)?.set(text, forKey: rawTextKey)
        }

        scheduleNotification()

        guard let url = URL(string: deepLinkURL) else {
            finish(success: true); return
        }

        // extensionContext.open works in share extensions on iOS 16+.
        // On earlier versions it silently fails; the notification is the fallback.
        extensionContext?.open(url) { [weak self] _ in
            self?.finish(success: true)
        }
    }

    // MARK: - Local notification

    /// Schedules an immediate notification after OCR so the user sees
    /// "Receipt scanned" regardless of whether the app opened automatically.
    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Receipt scanned"
        content.body  = "Expense ready to review"
        content.sound = .default
        content.userInfo = ["deepLink": deepLinkURL]

        // Short delay so the host app can come to foreground first on iOS 16+;
        // if it does, AppDelegate suppresses the banner. On older iOS the banner
        // fires and the user taps it to open the import screen.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        let id      = "trackora-share-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Extension lifecycle

    private func finish(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } else {
            extensionContext?.cancelRequest(
                withError: NSError(
                    domain: "com.michaelchia.trackora.ShareExtension",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Could not process image"]
                )
            )
        }
    }
}
