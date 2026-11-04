import Foundation

/// Reads SUPABASE_URL / SUPABASE_ANON_KEY that Config/*.xcconfig injects into Info.plist.
enum AppConfig {
    static let authCallbackURL = URL(string: "findme://login-callback")!
    static let urlScheme = "findme"

    static var supabaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty, !raw.contains("YOUR-PROJECT"),
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true, url.host != nil
        else { return nil }
        return url
    }

    static var supabaseAnonKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.hasPrefix("YOUR_")
        else { return nil }
        return key
    }

    /// FREE_TEAM = YES in the xcconfig (free Apple Personal Team): no Push / Sign in with Apple capability.
    static var isFreeTeam: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FINDME_FREE_TEAM") as? String)?.uppercased() == "YES"
    }

    static var isConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    /// Invite link that opens the app straight into the join flow (F-09 / F-16).
    static func joinLink(code: String) -> URL {
        URL(string: "findme://join/\(code)")!
    }
}
