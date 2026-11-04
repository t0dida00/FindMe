import Foundation
import Observation

/// Deep links (findme://join/CODE), notification taps and cross-screen navigation.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    /// Join code waiting to be confirmed (deep link may arrive before sign-in).
    var pendingJoinCode: String?
    /// Game to open (e.g. from a push notification tap or after join/create).
    var openGameId: UUID?

    func handle(url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }
        switch url.host {
        case "join":
            let code = url.pathComponents.dropFirst().first ?? ""
            let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber }
            if cleaned.count == 6 { pendingJoinCode = cleaned }
        case "game":
            if let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) { openGameId = id }
        default:
            break  // login-callback is consumed by ASWebAuthenticationSession / auth.handle
        }
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if let s = userInfo["game_id"] as? String, let id = UUID(uuidString: s) { openGameId = id }
    }
}
