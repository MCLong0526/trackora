import Flutter
import LinkPresentation
import UIKit

/// Presents Trackora receipt PNGs with the native iOS share sheet.
///
/// This bypasses share_plus for generated receipt images because the generic
/// file handoff can fail before the share sheet appears on some iOS devices.
class ReceiptShareService {
    static let channelName = "trackora/receipt_share"

    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: Self.channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler(handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "sharePngReceipt":
            sharePngReceipt(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func sharePngReceipt(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let typedData = args["bytes"] as? FlutterStandardTypedData else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Receipt PNG bytes are required.",
                details: nil
            ))
            return
        }

        guard let image = UIImage(data: typedData.data) else {
            result(FlutterError(
                code: "INVALID_IMAGE",
                message: "Receipt PNG could not be decoded.",
                details: nil
            ))
            return
        }

        let subject = args["subject"] as? String ?? "Trackora receipt"
        let origin = CGRect(
            x: Self.cgFloat(args["originX"]),
            y: Self.cgFloat(args["originY"]),
            width: Self.cgFloat(args["originWidth"]),
            height: Self.cgFloat(args["originHeight"])
        )

        DispatchQueue.main.async {
            guard let controller = Self.topViewController() else {
                result(FlutterError(
                    code: "NO_CONTROLLER",
                    message: "No view controller is available for sharing.",
                    details: nil
                ))
                return
            }

            let item = ReceiptImageActivityItem(image: image, subject: subject)
            let activityViewController = UIActivityViewController(
                activityItems: [item],
                applicationActivities: nil
            )
            activityViewController.setValue(subject, forKey: "subject")

            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = controller.view
                popover.sourceRect = Self.sourceRect(origin, in: controller.view)
            }

            activityViewController.completionWithItemsHandler = {
                activityType, completed, _, activityError in
                if let activityError {
                    result(FlutterError(
                        code: "SHARE_FAILED",
                        message: activityError.localizedDescription,
                        details: nil
                    ))
                    return
                }

                var response: [String: Any] = ["completed": completed]
                if let activityType {
                    response["activityType"] = activityType.rawValue
                }
                result(response)
            }

            controller.present(activityViewController, animated: true)
        }
    }

    private static func sourceRect(_ origin: CGRect, in view: UIView) -> CGRect {
        let bounds = view.bounds
        if !origin.isEmpty && bounds.contains(origin) {
            return origin
        }
        return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let int = value as? Int {
            return CGFloat(int)
        }
        return 0
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let root = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        return topViewController(from: root)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

private final class ReceiptImageActivityItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let subject: String

    init(image: UIImage, subject: String) {
        self.image = image
        self.subject = subject
        super.init()
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }

    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = subject
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}
