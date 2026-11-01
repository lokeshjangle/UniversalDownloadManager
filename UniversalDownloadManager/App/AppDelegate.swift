import UIKit

/// Application delegate for receiving system background URLSession completion callbacks.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let deepLinkNotification = Notification.Name("UniversalDownloadDeepLinkNotification")
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        NotificationCenter.default.post(name: Self.deepLinkNotification, object: url)
        return true
    }
    
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == BackgroundDownloadService.backgroundSessionIdentifier {
            // Save completion handler to call when urlSessionDidFinishEvents fires
            BackgroundDownloadService.shared.backgroundCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }
}

