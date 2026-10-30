import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Main view controller for the Share Extension.
/// Receives shared URLs from Chrome, Safari, and other iOS apps, validates them,
/// presents a Liquid Glass confirmation interface, and safely hands off to the main download queue.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    
    private var hostingController: UIHostingController<ShareSheetView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractSharedContent()
    }
    
    // MARK: - Content Extraction
    
    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            showError("No shared content found.")
            return
        }
        
        for item in items {
            guard let attachments = item.attachments, !attachments.isEmpty else { continue }
            
            // 1. Try URL attachment first
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (data, error) in
                        let resolvedURL: URL? = {
                            if let url = data as? URL { return url }
                            if let str = data as? String { return URL(string: str) }
                            return nil
                        }()
                        
                        DispatchQueue.main.async {
                            if let url = resolvedURL {
                                self?.processFoundURL(url)
                            } else {
                                self?.showError("Could not resolve valid URL.")
                            }
                        }
                    }
                    return
                }
            }
            
            // 2. Try Plain Text attachment (Chrome sometimes shares URLs as plain text)
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (data, error) in
                        let resolvedText = data as? String
                        DispatchQueue.main.async {
                            if let text = resolvedText {
                                self?.processSharedText(text)
                            } else {
                                self?.showError("Could not read shared text.")
                            }
                        }
                    }
                    return
                }
            }
        }
        
        showError("No compatible link found in shared content.")
    }
    
    private func processSharedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first HTTP/HTTPS link in text using detector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count))
            if let firstMatch = matches.first, let url = firstMatch.url {
                processFoundURL(url)
                return
            }
        }
        
        if let directURL = URL(string: trimmed), let scheme = directURL.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
            processFoundURL(directURL)
            return
        }
        
        showError("The shared text does not contain a valid HTTP or HTTPS link.")
    }
    
    private func processFoundURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else {
            showError("Only HTTP and HTTPS download links are supported (found: \(url.scheme ?? "unknown")).")
            return
        }
        
        guard let host = url.host, !host.isEmpty else {
            showError("Invalid URL: Missing host address.")
            return
        }
        
        // Suggest filename
        let filename: String
        let last = url.lastPathComponent
        if !last.isEmpty && last != "/" {
            filename = last.removingPercentEncoding ?? last
        } else {
            filename = "download"
        }
        
        presentConfirmationUI(url: url.absoluteString, suggestedFilename: filename, error: nil)
    }
    
    private func showError(_ message: String) {
        presentConfirmationUI(url: "", suggestedFilename: "", error: message)
    }
    
    // MARK: - Presentation
    
    private func presentConfirmationUI(url: String, suggestedFilename: String, error: String?) {
        let confirmationView = ShareSheetView(
            urlString: url,
            customFilename: suggestedFilename,
            errorMessage: error,
            onConfirm: { [weak self] confirmedURL, confirmedName in
                self?.handoffDownload(url: confirmedURL, filename: confirmedName)
            },
            onCancel: { [weak self] in
                self?.dismissExtension()
            }
        )
        
        let hosting = UIHostingController(rootView: confirmationView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hosting.didMove(toParent: self)
        self.hostingController = hosting
    }
    
    // MARK: - Safe Handoff
    
    private func handoffDownload(url: String, filename: String) {
        // 1. Preserve request safely in shared store (App Groups / fallback)
        let request = PendingDownloadRequest(
            urlString: url,
            customFilename: filename.isEmpty ? nil : filename,
            sourceApp: "Chrome"
        )
        PendingRequestsStore.shared.savePendingRequest(request)
        
        // 2. Build deep link
        var components = URLComponents()
        components.scheme = "universaldownload"
        components.host = "add"
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "name", value: filename)
        ]
        
        if let deepLinkURL = components.url {
            // Attempt to trigger main app via openURL
            openContainingApp(url: deepLinkURL)
        }
        
        // 3. Dismiss extension cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.dismissExtension()
        }
    }
    
    private func openContainingApp(url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
        
        // Fallback using extensionContext selector if supported by system
        let selector = sel_registerName("openURL:")
        var contextResponder: UIResponder? = self
        while let current = contextResponder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            contextResponder = current.next
        }
    }
    
    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
