import SwiftUI
import WebKit

/// Represents a media stream detected on the currently loaded webpage.
struct DetectedMediaItem: Identifiable, Equatable {
    let id = UUID()
    let mediaURL: URL
    let pageURL: URL?
    let title: String?
    let detectedAt: Date = Date()
}

/// In-App Web Browser with an intelligent background media sniffer.
/// Enables users to log into social platforms (like Instagram) once, browse stories or private accounts,
/// and download detected video streams directly to the Camera Roll in the background.
struct InAppBrowserView: View {
    @ObservedObject var store: DownloadStore
    @StateObject private var sessionManager = InstagramSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var initialURL: URL
    @State private var currentURLString: String = ""
    @State private var webTitle: String = "Browser"
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var webViewCommand: WebViewCommand?
    @State private var detectedMedia: DetectedMediaItem?
    @State private var showDownloadStartedAlert: Bool = false
    @State private var downloadStartedMessage: String = ""
    
    init(store: DownloadStore, initialURL: URL = URL(string: "https://www.instagram.com")!) {
        self.store = store
        _initialURL = State(initialValue: initialURL)
        _currentURLString = State(initialValue: initialURL.absoluteString)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Top Browser Address Bar
                    addressBarView
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accentColor)
                    }
                    
                    // Native WebKit View with Media Sniffer
                    WebViewContainer(
                        initialURL: initialURL,
                        currentURLString: $currentURLString,
                        webTitle: $webTitle,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        isLoading: $isLoading,
                        command: $webViewCommand,
                        onMediaDetected: { item in
                            handleDetectedMedia(item)
                        }
                    )
                    
                    // Bottom Navigation Bar
                    bottomBarView
                }
                
                // Floating Media Detection Banner
                if let media = detectedMedia {
                    detectedMediaBanner(for: media)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Download Confirmation Banner
                if showDownloadStartedAlert {
                    VStack {
                        GlassBadge(downloadStartedMessage, iconName: "arrow.down.circle.fill", color: AppTheme.successColor)
                            .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(webTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    sessionStatusPill
                }
            }
        }
    }
    
    // MARK: - Address Bar View
    
    private var addressBarView: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: isSecure ? "lock.fill" : "globe")
                    .font(.caption2)
                    .foregroundStyle(isSecure ? AppTheme.successColor : .secondary)
                
                TextField("Search or enter website name", text: $currentURLString)
                    .font(.subheadline)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        navigateToCurrentInput()
                    }
                
                if !currentURLString.isEmpty {
                    Button {
                        currentURLString = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6), in: .rect(cornerRadius: 10))
            
            Button {
                webViewCommand = .reload
            } label: {
                Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
    
    private var isSecure: Bool {
        currentURLString.lowercased().hasPrefix("https://")
    }
    
    // MARK: - Bottom Navigation Controls
    
    private var bottomBarView: some View {
        HStack {
            Button {
                webViewCommand = .goBack
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .disabled(!canGoBack)
            
            Spacer()
            
            Button {
                webViewCommand = .goForward
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(!canGoForward)
            
            Spacer()
            
            Button {
                if let igURL = URL(string: "https://www.instagram.com") {
                    webViewCommand = .loadURL(igURL)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.circle.fill")
                    Text("Instagram")
                        .font(.caption.bold())
                }
                .foregroundStyle(.purple)
            }
            
            Spacer()
            
            ShareLink(item: URL(string: currentURLString) ?? initialURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Session Status Pill
    
    private var sessionStatusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sessionManager.isLoggedIn ? AppTheme.successColor : .orange)
                .frame(width: 7, height: 7)
            
            Text(sessionManager.isLoggedIn ? "IG Active" : "Not Logged In")
                .font(.caption2.bold())
                .foregroundStyle(sessionManager.isLoggedIn ? AppTheme.successColor : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (sessionManager.isLoggedIn ? AppTheme.successColor : Color.orange).opacity(0.12),
            in: .capsule
        )
    }
    
    // MARK: - Detected Media Floating Banner
    
    @ViewBuilder
    private func detectedMediaBanner(for media: DetectedMediaItem) -> some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "film.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                        .frame(width: 36, height: 36)
                        .background(Color.purple.opacity(0.15), in: .circle)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video Stream Detected")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        Text(media.title ?? "Instagram Story / Video")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            detectedMedia = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button {
                    downloadDetectedMedia(media)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Video (Saves to Photos)")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: .rect(cornerRadius: 12)
                    )
                }
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
    
    // MARK: - Actions
    
    private func navigateToCurrentInput() {
        let trimmed = currentURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let lower = trimmed.lowercased()
        // Security check: Block dangerous non-web schemes
        if lower.hasPrefix("file:") || lower.hasPrefix("javascript:") || lower.hasPrefix("data:") || lower.hasPrefix("blob:") {
            currentURLString = initialURL.absoluteString
            return
        }
        
        let targetURL: URL
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            targetURL = URL(string: trimmed) ?? initialURL
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://\(trimmed)") ?? initialURL
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)") ?? initialURL
        }
        
        webViewCommand = .loadURL(targetURL)
    }
    
    private func handleDetectedMedia(_ item: DetectedMediaItem) {
        // Prevent spamming with the exact same media URL
        if detectedMedia?.mediaURL == item.mediaURL { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            detectedMedia = item
        }
    }
    
    private func downloadDetectedMedia(_ media: DetectedMediaItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Generate clean sanitized filename
        let filename: String
        let timestamp = Int(Date().timeIntervalSince1970)
        if let page = media.pageURL?.absoluteString, page.contains("/stories/") {
            let components = page.split(separator: "/")
            let rawUser = components.count > 4 ? String(components[4]) : "story"
            let safeUser = rawUser.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            let finalUser = safeUser.isEmpty ? "story" : safeUser
            filename = "Instagram_Story_\(finalUser)_\(timestamp).mp4"
        } else {
            filename = "Instagram_Video_\(timestamp).mp4"
        }
        
        store.addDownload(url: media.mediaURL, customFilename: filename)
        
        withAnimation {
            detectedMedia = nil
            downloadStartedMessage = "Download started! Will save to Photos."
            showDownloadStartedAlert = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showDownloadStartedAlert = false
            }
        }
    }
}

// MARK: - WebView Container & Script Injection

enum WebViewCommand: Equatable {
    case loadURL(URL)
    case goBack
    case goForward
    case reload
}

private struct WebViewContainer: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURLString: String
    @Binding var webTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var command: WebViewCommand?
    let onMediaDetected: (DetectedMediaItem) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use default persistent data store to keep Instagram cookies between launches
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Inject Media Sniffer JavaScript
        let snifferScript = """
        (function() {
            function notifyMedia(url, title) {
                if (!url || typeof url !== 'string') return;
                // Exclude data URLs or tiny blob placeholders
                if (url.startsWith('data:') || (url.startsWith('blob:') && url.length < 15)) return;
                
                // Only notify for mp4 or common media stream URLs
                if (url.includes('.mp4') || url.includes('cdninstagram.com') || url.includes('/video/') || url.includes('bytedance')) {
                    try {
                        window.webkit.messageHandlers.mediaSniffer.postMessage({
                            url: url,
                            title: title || document.title,
                            page: window.location.href
                        });
                    } catch(e) {}
                }
            }

            // Hook <video> play and loadeddata events
            document.addEventListener('play', function(e) {
                if (e.target && e.target.tagName === 'VIDEO') {
                    var src = e.target.currentSrc || e.target.src;
                    notifyMedia(src, document.title);
                }
            }, true);

            // Periodic inspection for active playing video elements
            setInterval(function() {
                var videos = document.getElementsByTagName('video');
                for (var i = 0; i < videos.length; i++) {
                    var v = videos[i];
                    var src = v.currentSrc || v.src;
                    if (src && (!v.paused || videos.length === 1)) {
                        notifyMedia(src, document.title);
                    }
                }
            }, 1200);
        })();
        """
        
        let userScript = WKUserScript(
            source: snifferScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "mediaSniffer")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Configure standard modern mobile Safari User-Agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        
        let req = URLRequest(url: initialURL)
        webView.load(req)
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let cmd = command {
            DispatchQueue.main.async {
                command = nil
            }
            switch cmd {
            case .loadURL(let targetURL):
                webView.load(URLRequest(url: targetURL))
            case .goBack:
                if webView.canGoBack { webView.goBack() }
            case .goForward:
                if webView.canGoForward { webView.goForward() }
            case .reload:
                webView.reload()
            }
        }
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: WebViewContainer
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                if let url = webView.url?.absoluteString {
                    self.parent.currentURLString = url
                }
                if let title = webView.title, !title.isEmpty {
                    self.parent.webTitle = title
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mediaSniffer",
                  let body = message.body as? [String: Any],
                  let urlString = body["url"] as? String,
                  let mediaURL = URL(string: urlString) else {
                return
            }
            
            // Security check: Only accept valid HTTP or HTTPS media streams
            guard let scheme = mediaURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return
            }
            
            // Security check: Prevent SSRF / internal intranet device scanning
            if DownloadCoordinator.shared.isPrivateOrLocalAddress(url: mediaURL) {
                return
            }
            
            let title = body["title"] as? String
            let pageURL = (body["page"] as? String).flatMap { URL(string: $0) }
            
            let item = DetectedMediaItem(
                mediaURL: mediaURL,
                pageURL: pageURL,
                title: title
            )
            
            DispatchQueue.main.async {
                self.parent.onMediaDetected(item)
            }
        }
    }
}

