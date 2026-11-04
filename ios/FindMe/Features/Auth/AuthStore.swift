import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

@MainActor @Observable
final class AuthStore {
    enum State: Equatable { case loading, signedOut, signedIn(UUID) }

    private(set) var state: State = .loading
    var errorMessage: String?
    var isWorking = false
    /// Raw nonce for the in-flight Sign in with Apple request.
    private var currentNonce: String?

    var userId: UUID? { if case .signedIn(let id) = state { return id }; return nil }

    func start() async {
        guard AppConfig.isConfigured else { state = .signedOut; return }
        for await (event, session) in Supa.client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if let session { state = .signedIn(session.user.id); PushManager.shared.userDidSignIn() }
                else { state = .signedOut }
            case .signedOut:
                state = .signedOut
            default:
                break
            }
        }
    }

    // MARK: Sign in with Apple (nonce → signInWithIdToken)

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = AppError.message(for: error)
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = String(localized: "Không nhận được thông tin đăng nhập từ Apple.")
                return
            }
            await run {
                _ = try await Supa.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
                // Apple only returns the name on the very first authorization; store it in the profile.
                if let name = credential.fullName {
                    let full = PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespaces)
                    if !full.isEmpty { try? await API.updateDisplayName(String(full.prefix(40))) }
                }
            }
        }
    }

    // MARK: Google (OAuth via ASWebAuthenticationSession → findme://login-callback)

    func signInWithGoogle() async {
        await run {
            _ = try await Supa.client.auth.signInWithOAuth(
                provider: .google, redirectTo: AppConfig.authCallbackURL
            ) { session in
                session.prefersEphemeralWebBrowserSession = false
            }
        }
    }

    // MARK: Email OTP (development)

    func sendOTP(email: String) async -> Bool {
        var ok = false
        await run {
            try await Supa.client.auth.signInWithOTP(email: email, shouldCreateUser: true)
            ok = true
        }
        return ok
    }

    func verifyOTP(email: String, code: String) async {
        await run {
            _ = try await Supa.client.auth.verifyOTP(email: email, token: code, type: .email)
        }
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        state = .signedOut
    }

    private func run(_ work: () async throws -> Void) async {
        guard AppConfig.isConfigured else {
            errorMessage = String(localized: "Chưa cấu hình Supabase (xem ios/README.md).")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do { try await work() } catch {
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
            errorMessage = AppError.message(for: error)
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
