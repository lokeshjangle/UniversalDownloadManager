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
    let qualityLabel: String?
    let estimatedSizeBytes: Int64?
    
    init(
        originalURL: URL,
        directURL: URL,
        filename: String,
        title: String?,
        platform: SupportedPlatform,
        qualityLabel: String? = nil,
        estimatedSizeBytes: Int64? = nil
    ) {
        self.originalURL = originalURL
        self.directURL = directURL
        self.filename = filename
        self.title = title
        self.platform = platform
        self.qualityLabel = qualityLabel
        self.estimatedSizeBytes = estimatedSizeBytes
    }
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
            // Instagram extraction is 100% on-device/client-side and does NOT use Cobalt API
            return try await resolveInstagramClientSide(url: url)
            
        case .youtube, .tiktok, .twitter:
            return try await resolveViaAPI(url: url, platform: platform)
        }
    }
    
    // MARK: - In-App Instagram Reel Extractor
    
    /// Represents a scored video stream candidate with detected resolution and bitrate.
    private struct ScoredVideoCandidate: Hashable {
        let url: URL
        var score: Int
        var qualityLabel: String
        var contentLength: Int64?
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
        
        static func == (lhs: ScoredVideoCandidate, rhs: ScoredVideoCandidate) -> Bool {
            lhs.url == rhs.url
        }
    }
    
    /// Direct in-app client-side scraper for public Instagram Reels without requiring any API keys.
    /// Evaluates multiple stream representations and selects the highest quality MP4 stream.
    private func resolveInstagramClientSide(url: URL) async throws -> ResolvedMediaItem {
        let shortcode = extractShortcode(from: url)
        
        // Candidate URLs to inspect in priority order
        var candidateURLs: [URL] = [
            url,
            URL(string: "https://www.instagram.com/reel/\(shortcode)/") ?? url,
            URL(string: "https://www.instagram.com/p/\(shortcode)/") ?? url,
            URL(string: "https://www.instagram.com/reel/\(shortcode)/embed/") ?? url,
            URL(string: "https://www.instagram.com/p/\(shortcode)/embed/") ?? url,
            URL(string: "https://www.instagram.com/reel/\(shortcode)/embed/captioned/") ?? url
        ]
        // Remove exact duplicates
        candidateURLs = candidateURLs.reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        
        let userAgents = [
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
        ]
        
        var collectedCandidates = Set<ScoredVideoCandidate>()
        var foundTitle: String?
        
        for candidate in candidateURLs {
            for ua in userAgents {
                var request = URLRequest(url: candidate)
                request.httpMethod = "GET"
                request.setValue(ua, forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.timeoutInterval = 8.0
                
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let html = String(data: data, encoding: .utf8) else {
                    continue
                }
                
                if foundTitle == nil {
                    foundTitle = extractMetaProperty(html: html, property: "og:title")
                }
                
                let candidatesInPage = extractAllVideoCandidates(from: html)
                for cand in candidatesInPage {
                    collectedCandidates.insert(cand)
                }
                
                // If we already found a full HD 1080p stream, we can proceed to verification
                if collectedCandidates.contains(where: { $0.qualityLabel.contains("1080") }) {
                    break
                }
            }
            
            if collectedCandidates.contains(where: { $0.qualityLabel.contains("1080") }) {
                break
            }
        }
        
        guard !collectedCandidates.isEmpty else {
            throw NSError(domain: "MediaResolverError", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Unable to extract video from this Instagram link. The post may be from a private account, or you can open it in Safari and download with our Safari Web Extension."
            ])
        }
        
        // Sort candidates by initial score descending
        let sortedInitial = collectedCandidates.sorted { $0.score > $1.score }
        let topCandidates = Array(sortedInitial.prefix(3))
        
        // Perform concurrent HEAD probes on top candidates to check accessibility and content length
        var verifiedCandidates: [ScoredVideoCandidate] = []
        await withTaskGroup(of: ScoredVideoCandidate?.self) { group in
            for cand in topCandidates {
                group.addTask {
                    await self.probeCandidateQuality(candidate: cand)
                }
            }
            for await verified in group {
                if let verified {
                    verifiedCandidates.append(verified)
                }
            }
        }
        
        // Pick best verified candidate, or fallback to the highest scored initial candidate
        let bestCandidate: ScoredVideoCandidate
        if let topVerified = verifiedCandidates.max(by: {
            ($0.contentLength ?? 0) < ($1.contentLength ?? 0)
        }) {
            bestCandidate = topVerified
        } else if let firstInitial = sortedInitial.first {
            bestCandidate = firstInitial
        } else {
            throw NSError(domain: "MediaResolverError", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Unable to verify a valid playable video stream for this reel."
            ])
        }
        
        let filename = "Instagram_Reel_\(shortcode).mp4"
        return ResolvedMediaItem(
            originalURL: url,
            directURL: bestCandidate.url,
            filename: filename,
            title: foundTitle,
            platform: .instagram,
            qualityLabel: bestCandidate.qualityLabel,
            estimatedSizeBytes: bestCandidate.contentLength
        )
    }
    
    /// Probes a video candidate with an HTTP HEAD request to verify accessibility and file size.
    private func probeCandidateQuality(candidate: ScoredVideoCandidate) async -> ScoredVideoCandidate? {
        var req = URLRequest(url: candidate.url)
        req.httpMethod = "HEAD"
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 4.0
        
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        
        var updated = candidate
        let length = http.expectedContentLength
        if length > 0 {
            updated.contentLength = length
            updated.score += Int(length / 1024) // Higher file size = higher bitrate
            if length > 5_000_000 && !updated.qualityLabel.contains("1080") {
                updated.qualityLabel = "High Bitrate HD"
            }
        }
        return updated
    }
    
    /// Extracts and scores all video stream candidates present in the HTML document.
    private func extractAllVideoCandidates(from html: String) -> [ScoredVideoCandidate] {
        var foundRawURLs = Set<String>()
        
        // 1. Direct scan for JSON video stream attributes (video_url, playback_url, contentUrl)
        let keys = ["video_url", "playback_url", "contentUrl"]
        for key in keys {
            var searchStart = html.startIndex
            while let keyRange = html[searchStart...].range(of: key) {
                let afterKey = html[keyRange.upperBound...]
                if let httpRange = afterKey.range(of: "https:") {
                    let distance = html.distance(from: keyRange.upperBound, to: httpRange.lowerBound)
                    if distance < 30 {
                        let fromHttp = afterKey[httpRange.lowerBound...]
                        var urlEndIndex = fromHttp.endIndex
                        for delimiter in ["\\\"", "\"", "&quot;", "\\\\\"", "}", "]", "<", " "] {
                            if let delimRange = fromHttp.range(of: delimiter) {
                                if delimRange.lowerBound < urlEndIndex {
                                    urlEndIndex = delimRange.lowerBound
                                }
                            }
                        }
                        
                        let raw = cleanURLString(String(fromHttp[..<urlEndIndex]))
                        if raw.contains(".mp4") {
                            foundRawURLs.insert(raw)
                        }
                    }
                }
                searchStart = keyRange.upperBound
            }
        }
        
        // 2. Scan DASH Manifest <BaseURL> elements
        if let manifestRange = html.range(of: "video_dash_manifest") {
            let manifestSlice = html[manifestRange.upperBound...]
            var searchStart = manifestSlice.startIndex
            while let baseStart = manifestSlice[searchStart...].range(of: "https:") {
                let fromHttp = manifestSlice[baseStart.lowerBound...]
                var urlEndIndex = fromHttp.endIndex
                for delimiter in ["\\\"", "\"", "&quot;", "\\\\\"", "<", " ", ">"] {
                    if let delimRange = fromHttp.range(of: delimiter) {
                        if delimRange.lowerBound < urlEndIndex {
                            urlEndIndex = delimRange.lowerBound
                        }
                    }
                }
                let raw = cleanURLString(String(fromHttp[..<urlEndIndex]))
                if raw.contains(".mp4") {
                    foundRawURLs.insert(raw)
                }
                searchStart = baseStart.upperBound
                if html.distance(from: manifestRange.upperBound, to: searchStart) > 25000 {
                    break
                }
            }
        }
        
        // 3. OpenGraph & HTML5 video element regex fallback
        let patterns = [
            "<meta\\s+property=[\"']og:video(?::secure_url)?[\"']\\s+content=[\"']([^\"']+)[\"']",
            "<meta\\s+content=[\"']([^\"']+)[\"']\\s+property=[\"']og:video(?::secure_url)?[\"']",
            "<video[^>]+src=[\"']([^\"']+)[\"']"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: html) {
                        let raw = cleanURLString(String(html[range]))
                        if raw.contains(".mp4") || raw.contains("fbcdn.net") {
                            foundRawURLs.insert(raw)
                        }
                    }
                }
            }
        }
        
        // Score each candidate and filter out audio-only tracks
        var candidates: [ScoredVideoCandidate] = []
        for rawURL in foundRawURLs {
            if let candidate = scoreAndCategorize(rawURL: rawURL) {
                candidates.append(candidate)
            }
        }
        return candidates
    }
    
    private func cleanURLString(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "\\\\", with: "")
        s = s.replacingOccurrences(of: "\\/", with: "/")
        s = s.replacingOccurrences(of: "\\u0026", with: "&")
        s = s.replacingOccurrences(of: "\\u00253D", with: "=")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Evaluates a raw video stream URL, checks encoding tags in `efg=`, and assigns a quality score.
    private func scoreAndCategorize(rawURL: String) -> ScoredVideoCandidate? {
        guard let url = URL(string: rawURL), url.scheme == "https" else { return nil }
        
        var score = 100
        var label = "720p HD"
        
        // Inspect efg parameter (base64 JSON containing vencode_tag and bitrate)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let efgParam = components.queryItems?.first(where: { $0.name == "efg" })?.value {
            var rawB64 = efgParam
                .replacingOccurrences(of: "%3D", with: "=")
                .replacingOccurrences(of: "%2F", with: "/")
                .replacingOccurrences(of: "%2B", with: "+")
            let pad = rawB64.count % 4
            if pad > 0 {
                rawB64.append(String(repeating: "=", count: 4 - pad))
            }
            
            if let data = Data(base64Encoded: rawB64),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let tag = (json["vencode_tag"] as? String)?.lowercased() ?? ""
                
                // Exclude pure audio streams
                if tag.contains("audio") || tag.contains("heaac") {
                    return nil
                }
                
                if tag.contains("1080") {
                    score += 10000
                    label = "1080p Full HD"
                } else if tag.contains("720") {
                    score += 5000
                    label = "720p HD"
                } else if tag.contains("480") {
                    score += 2000
                    label = "480p SD"
                } else if tag.contains("360") {
                    score += 500
                    label = "360p SD"
                }
                
                if let bitrate = json["bitrate"] as? Int {
                    score += bitrate / 1000
                }
                if tag.contains("dash_high") {
                    score += 2500
                }
            }
        }
        
        if rawURL.contains("1080") && !label.contains("1080") {
            score += 8000
            label = "1080p Full HD"
        } else if rawURL.contains("720") && !label.contains("720") {
            score += 4000
        }
        
        return ScoredVideoCandidate(url: url, score: score, qualityLabel: label, contentLength: nil)
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
