import Foundation
import WebKit
import Combine

/// Service managing persistent Instagram authentication sessions and cookies across app restarts.
/// Automatically detects login changes inside the In-App Browser WKWebView and exposes session headers
/// for authenticated Instagram Story and private profile downloads.
@MainActor
final class InstagramSessionManager: NSObject, ObservableObject, WKHTTPCookieStoreObserver {
    static let shared = InstagramSessionManager()
    
    /// Whether a verified logged-in session exists (detected via `sessionid` and `ds_user_id` cookies).
    @Published private(set) var isLoggedIn: Bool = false
    
    /// User identifier or username associated with current session.
    @Published private(set) var currentUserId: String?
    
    /// Active cookie string formatted for `Cookie: ...` HTTP request headers.
    @Published private(set) var cookieHeader: String?
    
    /// Timestamp of last cookie verification.
    @Published private(set) var lastSyncDate: Date?
    
    private let cookieStore: WKHTTPCookieStore
    
    private override init() {
        self.cookieStore = WKWebsiteDataStore.default().httpCookieStore
        super.init()
        
        cookieStore.add(self)
        Task {
            await refreshSession()
        }
    }
    
    // MARK: - WKHTTPCookieStoreObserver
    
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            await self.refreshSession()
        }
    }
    
    // MARK: - Domain Safety Validation
    
    private func isInstagramDomain(_ domain: String) -> Bool {
        let clean = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return clean == "instagram.com" || clean.hasSuffix(".instagram.com") ||
               clean == "instagr.am" || clean.hasSuffix(".instagr.am")
    }
    
    // MARK: - Session Sync
    
    /// Queries the WebKit persistent cookie store for Instagram session tokens.
    func refreshSession() async {
        let cookies = await fetchCookies()
        let igCookies = cookies.filter { isInstagramDomain($0.domain) }
        
        let sessionCookie = igCookies.first { $0.name == "sessionid" && !$0.value.isEmpty }
        let userCookie = igCookies.first { $0.name == "ds_user_id" && !$0.value.isEmpty }
        
        if let sessionCookie, !sessionCookie.value.isEmpty {
            self.isLoggedIn = true
            self.currentUserId = userCookie?.value
            
            // Format valid Cookie header string
            let pairs = igCookies.map { "\($0.name)=\($0.value)" }
            self.cookieHeader = pairs.joined(separator: "; ")
        } else {
            self.isLoggedIn = false
            self.currentUserId = nil
            self.cookieHeader = nil
        }
        
        self.lastSyncDate = Date()
    }
    
    /// Logs out of Instagram by clearing all Instagram-related cookies and storage.
    func clearSession() async {
        let cookies = await fetchCookies()
        for cookie in cookies where isInstagramDomain(cookie.domain) {
            await deleteCookie(cookie)
        }
        
        // Also clear website data
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await fetchWebsiteDataRecords(ofTypes: dataTypes)
        let igRecords = records.filter { isInstagramDomain($0.displayName) }
        await removeWebsiteData(for: igRecords, ofTypes: dataTypes)
        
        await refreshSession()
    }
    
    // MARK: - Asynchronous WebKit Helpers
    
    private func fetchCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
    
    private func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }
    
    private func fetchWebsiteDataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
    }
    
    private func removeWebsiteData(for records: [WKWebsiteDataRecord], ofTypes types: Set<String>) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(ofTypes: types, for: records) {
                continuation.resume()
            }
        }
    }
}

