import Flutter
import Foundation
import UIKit

/// Bridges the iOS Share Extension → main app import flow.
///
/// The Share Extension saves the image and pre-computed OCR text into the App
/// Group container. This service reads both, then exposes the result to Flutter
/// via the `trackora/share_import` channel.
///
/// Channel methods (Native → Flutter):
///   `onShareImport`       — triggered when `trackora://import-receipt` is opened.
///
/// Channel methods (Flutter → Native):
///   `checkPendingShare`   → Map?  { imagePath: String, rawText: String } or null
///   `clearPendingShare`   → void
class ShareImportService {
    static let channelName = "trackora/share_import"
    static let appGroupId  = "group.com.michaelchia.trackora"

    private static let pendingImageName = "pending_share_image.jpg"
    private static let timestampKey     = "pendingShareTimestamp"
    private static let rawTextKey       = "pendingShareRawText"
    // Ignore shares older than 5 min (handles slow Firebase init + user delays).
    private static let maxAgeSeconds: TimeInterval = 300

    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: Self.channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler(handle)
    }

    // MARK: - Method call handler

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPendingShare":
            checkPendingShare(result: result)
        case "clearPendingShare":
            clearPendingShare(result: result)
        case "runOcrOnImage":
            runOcrOnImage(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Notify Flutter

    func notifyShareImport() {
        channel.invokeMethod("onShareImport", arguments: nil)
    }

    // MARK: - Pending share logic

    private func containerImageURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupId
        ) else { return nil }
        return container.appendingPathComponent(Self.pendingImageName)
    }

    private func checkPendingShare(result: @escaping FlutterResult) {
        guard let imageURL = containerImageURL(),
              FileManager.default.fileExists(atPath: imageURL.path) else {
            result(nil)
            return
        }

        // Reject stale images so startup checks don't re-open old imports.
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        let timestamp = defaults?.double(forKey: Self.timestampKey) ?? 0
        let age = Date().timeIntervalSince1970 - timestamp
        if age > Self.maxAgeSeconds {
            clearStoredFiles()
            result(nil)
            return
        }

        // Use rawText pre-computed by the Share Extension when available,
        // so we skip re-running OCR in the main app.
        if let precomputed = defaults?.string(forKey: Self.rawTextKey),
           !precomputed.isEmpty {
            result([
                "imagePath": imageURL.path,
                "rawText": precomputed
            ])
            return
        }

        // Fallback: run OCR here if the extension didn't produce rawText.
        OcrService.performOcr(imagePath: imageURL.path) { rawText in
            DispatchQueue.main.async {
                result([
                    "imagePath": imageURL.path,
                    "rawText": rawText ?? ""
                ])
            }
        }
    }

    private func clearPendingShare(result: @escaping FlutterResult) {
        clearStoredFiles()
        result(nil)
    }

    // MARK: - Camera OCR (called from Flutter image_picker flow)

    private func runOcrOnImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "imagePath required", details: nil))
            return
        }
        OcrService.performOcr(imagePath: imagePath) { rawText in
            DispatchQueue.main.async {
                result(rawText ?? "")
            }
        }
    }

    private func clearStoredFiles() {
        if let url = containerImageURL() {
            try? FileManager.default.removeItem(at: url)
        }
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        defaults?.removeObject(forKey: Self.timestampKey)
        defaults?.removeObject(forKey: Self.rawTextKey)
    }
}
