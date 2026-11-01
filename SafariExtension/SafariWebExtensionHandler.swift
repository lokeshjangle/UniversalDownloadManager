import SafariServices
import Foundation
import os.log

/// Native Swift messaging handler for the Safari Web Extension.
/// Receives structured download requests from the Safari toolbar popup or content script,
/// validates the target URL, stores the request in the authoritative pending queue,
/// and returns confirmation back to Safari JavaScript.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    private let logger = Logger(subsystem: "com.lokeshjangale.UniversalDownloadManager.SafariExtension", category: "ExtensionHandler")
    
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem else {
            respond(with: ["status": "error", "message": "No input items provided"], context: context)
            return
        }
        
        let messagePayload: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            messagePayload = item.userInfo?[SFExtensionMessageKey]
        } else {
            messagePayload = item.userInfo?["message"]
        }
        
        guard let messageDict = messagePayload as? [String: Any] else {
            respond(with: ["status": "error", "message": "Invalid message format"], context: context)
            return
        }
        
        let action = messageDict["action"] as? String ?? ""
        
        switch action {
        case "enqueueDownload":
            handleEnqueueDownload(messageDict, context: context)
        case "ping":
            respond(with: ["status": "ok", "app": "UniversalDownloadManager"], context: context)
        default:
            respond(with: ["status": "error", "message": "Unknown action '\(action)'"], context: context)
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleEnqueueDownload(_ payload: [String: Any], context: NSExtensionContext) {
        guard let rawURLString = payload["url"] as? String,
              let url = validateDownloadURL(rawURLString) else {
            respond(with: [
                "status": "error",
                "message": "Unsupported or malformed URL. Only HTTP and HTTPS links are allowed."
            ], context: context)
            return
        }
        
        let suggestedName = (payload["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFilename: String
        if let custom = suggestedName, !custom.isEmpty {
            finalFilename = custom
        } else {
            finalFilename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        }
        
        // 1. Save request in thread-safe shared store
        let request = PendingDownloadRequest(
            urlString: url.absoluteString,
            customFilename: finalFilename,
            sourceApp: "Safari"
        )
        PendingRequestsStore.shared.savePendingRequest(request)
        logger.info("Safari extension queued download: \(url.absoluteString, privacy: .public)")
        
        // 2. Respond to extension JavaScript
        respond(with: [
            "status": "accepted",
            "message": "Download queued for background transfer.",
            "url": url.absoluteString,
            "filename": finalFilename
        ], context: context)
    }
    
    // MARK: - Validation
    
    private func validateDownloadURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else {
            return nil
        }
        guard let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
    
    // MARK: - Response Helper
    
    private func respond(with responseData: [String: Any], context: NSExtensionContext) {
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [SFExtensionMessageKey: responseData]
        } else {
            responseItem.userInfo = ["message": responseData]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }
}

