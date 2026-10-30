import Foundation
import Combine

/// Represents supported media platforms detected from URL patterns.
enum SupportedPlatform: String, CaseIterable, Identifiable, Sendable {
    case direct = "Direct File"
    case instagram = "Instagram Reel"
    case youtube = "YouTube"
    case tiktok = "TikTok"
    case twitter = "X / Twitter"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .direct: return "arrow.down.circle.fill"
        case .instagram: return "camera.circle.fill"
        case .youtube: return "play.rectangle.fill"
        case .tiktok: return "music.note"
        case .twitter: return "bubble.left.and.bubble.right.fill"
        }
    }
}

/// Represents the resolved direct stream information ready for downloading.
struct ResolvedMediaItem: Sendable {
    let originalURL: URL
    let directURL: URL
    let filename: String
    let title: String?
    let platform: SupportedPlatform
}

/// Service that detects social and streaming video URLs and resolves them into direct downloadable MP4 streams.
final class MediaResolverService: Sendable {
    static let shared = MediaResolverService()
    
    private let defaultResolverEndpoint = "https://api.cobalt.tools"
    private let endpointUserDefaultsKey = "UDM_CustomResolverEndpoint"
    private let apiKeyUserDefaultsKey = "UDM_CustomResolverAPIKey"
    
    private init() {}
    
    // MARK: - Configuration
    
    /// The current resolver API endpoint (defaults to Cobalt public instance, configurable in Settings).
    var resolverEndpoint: String {
        get {
            let saved = UserDefaults.standard.string(forKey: endpointUserDefaultsKey)
            let trimmed = saved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? defaultResolverEndpoint : trimmed
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: endpointUserDefaultsKey)
        }
    }
    
    /// Optional API Key or Bearer token for protected resolver instances.
    var resolverAPIKey: String {
        get {
            UserDefaults.standard.string(forKey: apiKeyUserDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyUserDefaultsKey)
        }
    }
    
    // MARK: - Platform Detection
    
    /// Analyzes a URL and identifies whether it is a streaming service or a direct file.
    func detectPlatform(from url: URL) -> SupportedPlatform {
        guard let host = url.host?.lowercased() else { return .direct }
        let path = url.path.lowercased()
        
        if host.contains("instagram.com") || host.contains("instagr.am") {
            if path.contains("/reel") || path.contains("/p/") || path.contains("/tv/") {
                return .instagram
            }
        }
        
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        }
        
        if host.contains("tiktok.com") {
            return .tiktok
        }
        
        if host.contains("twitter.com") || host.contains("x.com") {
            return .twitter
        }
        
        return .direct
    }
    
    // MARK: - Stream Resolution
    
    /// Resolves a URL into a direct downloadable MP4 URL.
    /// If already a direct file, returns the URL immediately.
    func resolve(url: URL) async throws -> ResolvedMediaItem {
        let platform = detectPlatform(from: url)
        
        switch platform {
        case .direct:
            let lastComponent = url.lastPathComponent
            let filename = (lastComponent.isEmpty || lastComponent == "/") ? "download" : (lastComponent.removingPercentEncoding ?? lastComponent)
            return ResolvedMediaItem(
                originalURL: url,
                directURL: url,
                filename: filename,
                title: nil,
                platform: .direct
            )
            
        case .instagram:
            // 1. Attempt direct in-app extraction via OpenGraph / schema metadata (fastest, private)
            if let directResult = try? await resolveInstagramClientSide(url: url) {
                return directResult
            }
            // 2. Fallback to resolver API if client-side extraction encounters login wall
            return try await resolveViaAPI(url: url, platform: .instagram)
            
        case .youtube, .tiktok, .twitter:
            return try await resolveViaAPI(url: url, platform: platform)
        }
    }
    
    // MARK: - In-App Instagram Reel Extractor
    
    /// Direct in-app client-side scraper for public Instagram Reels without requiring any API keys.
    private func resolveInstagramClientSide(url: URL) async throws -> ResolvedMediaItem {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 12.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MediaResolverError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to load Instagram webpage."])
        }
        
        // Extract direct CDN video URL
        guard let directURLString = extractVideoURLFromHTML(html),
              let directURL = URL(string: directURLString) else {
            throw NSError(domain: "MediaResolverError", code: 422, userInfo: [NSLocalizedDescriptionKey: "No public video stream found on this Instagram page."])
        }
        
        // Derive clean filename and title
        let shortcode = extractShortcode(from: url)
        let filename = "Instagram_Reel_\(shortcode).mp4"
        let title = extractMetaProperty(html: html, property: "og:title")
        
        return ResolvedMediaItem(
            originalURL: url,
            directURL: directURL,
            filename: filename,
            title: title,
            platform: .instagram
        )
    }
    
    private func extractVideoURLFromHTML(_ html: String) -> String? {
        let patterns = [
            "<meta\\s+property=[\"']og:video(?::secure_url)?[\"']\\s+content=[\"']([^\"']+)[\"']",
            "<meta\\s+content=[\"']([^\"']+)[\"']\\s+property=[\"']og:video(?::secure_url)?[\"']",
            "\"contentUrl\"\\s*:\\s*\"([^\"]+)\"",
            "\"video_url\"\\s*:\\s*\"([^\"]+)\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                var raw = String(html[range])
                raw = raw.replacingOccurrences(of: "\\/", with: "/")
                raw = raw.replacingOccurrences(of: "\\u0026", with: "&")
                raw = raw.replacingOccurrences(of: "&amp;", with: "&")
                return raw
            }
        }
        return nil
    }
    
    private func extractMetaProperty(html: String, property: String) -> String? {
        let pattern = "<meta\\s+property=[\"']\(property)[\"']\\s+content=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let raw = String(html[range])
        return raw.replacingOccurrences(of: "&amp;", with: "&")
    }
    
    private func extractShortcode(from url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let reelIndex = components.firstIndex(where: { $0 == "reel" || $0 == "p" || $0 == "tv" }),
           reelIndex + 1 < components.count {
            return components[reelIndex + 1]
        }
        return String(UUID().uuidString.prefix(8))
    }
    
    // MARK: - Multi-Platform Resolver API (Cobalt / Universal API)
    
    private func resolveViaAPI(url: URL, platform: SupportedPlatform) async throws -> ResolvedMediaItem {
        guard let apiBase = URL(string: resolverEndpoint) else {
            throw NSError(domain: "MediaResolverError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid resolver API endpoint in Settings."])
        }
        
        var request = URLRequest(url: apiBase)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UniversalDownloadManager/1.0", forHTTPHeaderField: "User-Agent")
        
        let apiKey = resolverAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            if apiKey.lowercased().hasPrefix("bearer ") || apiKey.lowercased().hasPrefix("api-key ") {
                request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Api-Key \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        request.timeoutInterval = 20.0
        
        let payload: [String: Any] = [
            "url": url.absoluteString,
            "videoQuality": "1080",
            "filenameStyle": "pretty"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NSError(domain: "MediaResolverError", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "Unable to reach the stream resolver service (\(apiBase.host ?? "API")). Please check your internet connection or update the resolver endpoint in Settings."
            ])
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MediaResolverError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Malformed response from resolver API."])
        }
        
        // Parse Cobalt / Generic Resolver JSON response
        struct APIResult: Decodable {
            let status: String?
            let url: String?
            let filename: String?
            let text: String?
            struct PickerItem: Decodable {
                let type: String?
                let url: String
            }
            let picker: [PickerItem]?
            struct APIError: Decodable {
                let code: String?
            }
            let error: APIError?
        }
        
        guard let result = try? JSONDecoder().decode(APIResult.self, from: data) else {
            let rawString = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw NSError(domain: "MediaResolverError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Resolver API returned an unexpected response format: \(rawString.prefix(100))"
            ])
        }
        
        if let errCode = result.error?.code {
            if errCode.contains("auth") || errCode.contains("jwt") || errCode.contains("key") {
                throw NSError(domain: "MediaResolverError", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Authentication required by '\(apiBase.host ?? "API")'. The official api.cobalt.tools requires an API key or a self-hosted instance. Add your API key or point to your instance in Settings."
                ])
            }
            throw NSError(domain: "MediaResolverError", code: 422, userInfo: [
                NSLocalizedDescriptionKey: "Resolver API error: \(errCode)"
            ])
        }
        
        // Find direct stream URL from either direct url or picker item
        var resolvedStreamURLString: String? = result.url
        if resolvedStreamURLString == nil, let picker = result.picker, let firstVideo = picker.first(where: { $0.type == "video" }) ?? picker.first {
            resolvedStreamURLString = firstVideo.url
        }
        
        guard let finalURLString = resolvedStreamURLString, let streamURL = URL(string: finalURLString) else {
            throw NSError(domain: "MediaResolverError", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "The resolver service could not find a streamable video link for this URL."
            ])
        }
        
        let derivedFilename = result.filename ?? "\(platform.rawValue)_\(UUID().uuidString.prefix(6)).mp4"
        let safeFilename = derivedFilename.hasSuffix(".mp4") ? derivedFilename : "\(derivedFilename).mp4"
        
        return ResolvedMediaItem(
            originalURL: url,
            directURL: streamURL,
            filename: safeFilename,
            title: result.filename,
            platform: platform
        )
    }
}
