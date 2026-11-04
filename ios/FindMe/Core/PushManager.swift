import Foundation
import UIKit
import UserNotifications

/// F-24: asks for notification permission, registers for APNs and sends the token with
/// rpc register_device_token(p_token, 'ios'). Push sending itself happens server-side (Edge Function).
@MainActor
final class PushManager {
    static let shared = PushManager()
    private var token: String?
    private var registeredToken: String?
    private var signedIn = false

    func requestAuthorizationIfNeeded() {
        // A free Personal Team cannot sign the aps-environment entitlement.
        guard !AppConfig.isFreeTeam else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            case .authorized, .provisional, .ephemeral:
                UIApplication.shared.registerForRemoteNotifications()
            default:
                break
            }
        }
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        uploadIfPossible()
    }

    func userDidSignIn() {
        signedIn = true
        uploadIfPossible()
    }

    private func uploadIfPossible() {
        guard signedIn, let token, token != registeredToken else { return }
        Task {
            do {
                try await API.registerDeviceToken(token)
                registeredToken = token
            } catch {
                print("register_device_token failed: \(error)")
            }
        }
    }
}
