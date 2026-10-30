import UIKit

/// Application delegate for receiving system background URLSession completion callbacks.
final class AppDelegate: NSObject, UIApplicationDelegate {
    
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
