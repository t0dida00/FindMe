import Foundation

/// Player calls to the Find Me! server (Go API, `GoAPI`). The server holds every game rule; the app
/// only asks and shows the answer. Supabase is used for sign-in only (`Supa`), and photos go to
/// Storage through URLs the server signs.
enum API {
    static func requireUser() throws -> UUID {
        guard let id = Supa.currentUserId else { throw APIError.notSignedIn }
        return id
    }

    enum APIError: LocalizedError {
        case notSignedIn, compressionFailed, uploadDeadlinePassed
        var errorDescription: String? {
            switch self {
            case .notSignedIn: String(localized: "Bạn cần đăng nhập lại.")
            case .compressionFailed: String(localized: "Không nén được ảnh.")
            case .uploadDeadlinePassed: String(localized: "Đã quá thời hạn tải ảnh.")
            }
        }
    }

    static func id(_ u: UUID) -> String { u.uuidString.lowercased() }

    // MARK: Joining

    /// Joins the unfinished game with this join code.
    static func joinGame(code: String) async throws -> UUID {
        struct R: Decodable { let gameId: UUID }
        return try await GoAPI.write("POST", "/v1/games/join", body: ["code": code], as: R.self).gameId
    }

    /// Joins a public "open to everyone" game without a code.
    static func joinOpenGame(gameId: UUID) async throws -> UUID {
        struct R: Decodable { let gameId: UUID }
        return try JSONCoding.decoder.decode(R.self, from: try await GoAPI.send("POST", "/v1/games/\(id(gameId))/join")).gameId
    }

    // MARK: Playing

    /// Blocks players may see: the current hint's (once their timer is up) and every solved hint's.
    static func hintItems(gameId: UUID) async throws -> [HintItemRow] {
        try await GoAPI.get("/v1/games/\(id(gameId))/hint-items")
    }

    /// The hint being hunted (works even when none of its blocks is visible yet); nil if none.
    static func currentHint(gameId: UUID) async throws -> CurrentHintRow? {
        try await GoAPI.getOptional("/v1/games/\(id(gameId))/current-hint", as: CurrentHintRow.self)
    }

    /// When the next timed block of the current hint opens, if any.
    static func nextRevealAt(gameId: UUID) async throws -> Date? {
        try await GoAPI.get("/v1/games/\(id(gameId))/next-reveal")
    }

    /// 'open' | 'in_review' | 'solved' | nil
    static func currentCodeStatus(gameId: UUID) async throws -> CodeStatus? {
        (try await GoAPI.get("/v1/games/\(id(gameId))/code-status", as: String?.self)).flatMap(CodeStatus.init(rawValue:))
    }

    /// Tries left before the lock, or until when code entry is locked.
    static func myCodeState(hintId: UUID) async throws -> MyCodeState {
        try await GoAPI.get("/v1/hints/\(id(hintId))/my-code-state")
    }

    /// Step 1 of a find: the code printed at the location.
    static func redeemCode(hintId: UUID, code: String) async throws -> RedeemResult {
        try await GoAPI.write("POST", "/v1/hints/\(id(hintId))/redeem", body: ["code": code], as: RedeemResult.self)
    }

    /// Step 2: the uploaded proof photo (path returned by `newUpload`).
    static func attachPhoto(submissionId: UUID, path: String) async throws {
        try await GoAPI.write("POST", "/v1/submissions/\(id(submissionId))/photo", body: ["path": path])
    }

    static func revealedAnswers(gameId: UUID) async throws -> [RevealedAnswer] {
        try await GoAPI.get("/v1/games/\(id(gameId))/revealed-answers")
    }

    static func leaderboard(gameId: UUID) async throws -> [LeaderboardEntry] {
        try await GoAPI.get("/v1/games/\(id(gameId))/leaderboard")
    }

    // MARK: Globe, rankings, profile stats

    /// Public games (not draft/cancelled) + my own games that have an area. Never includes join codes.
    static func globeGames() async throws -> [GlobeGame] {
        try await GoAPI.get("/v1/globe")
    }

    /// Top `limit` + my own row if I'm outside the top.
    static func playerRankings(limit: Int = 100) async throws -> [PlayerRankingEntry] {
        try await GoAPI.get("/v1/rankings/players", query: ["limit": "\(limit)"])
    }

    static func hostRankings(limit: Int = 100) async throws -> [HostRankingEntry] {
        try await GoAPI.get("/v1/rankings/hosts", query: ["limit": "\(limit)"])
    }

    static func myStats() async throws -> MyStats? {
        try await GoAPI.get("/v1/me/stats", as: MyStats?.self)
    }

    static func myHistory(limit: Int = 50) async throws -> [HistoryEntry] {
        struct Items: Decodable { let items: [HistoryEntry] }
        return try await GoAPI.get("/v1/me/history", query: ["limit": "\(limit)"], as: Items.self).items
    }

    /// Players rate the host 1–5 stars after the game is completed/cancelled. Re-rating overwrites.
    static func rateHost(gameId: UUID, stars: Int) async throws {
        try await GoAPI.write("PUT", "/v1/games/\(id(gameId))/rating", body: ["stars": stars])
    }

    static func myHostRating(gameId: UUID) async throws -> Int? {
        try await GoAPI.get("/v1/games/\(id(gameId))/my-rating")
    }

    // MARK: Games and people

    static func game(id gameId: UUID) async throws -> Game {
        try await GoAPI.get("/v1/games/\(id(gameId))")
    }

    static func myGames() async throws -> [MyGameEntry] {
        try await GoAPI.get("/v1/me/games")
    }

    /// Host name, player count, x/y hints solved (members of the game only).
    static func gameSummary(gameId: UUID) async throws -> GameSummary? {
        try await GoAPI.getOptional("/v1/games/\(id(gameId))/summary", as: GameSummary.self)
    }

    static func participants(gameId: UUID) async throws -> [Participant] {
        try await GoAPI.get("/v1/games/\(id(gameId))/participants")
    }

    static func profiles(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        return try await GoAPI.get("/v1/profiles", query: ["ids": GoAPI.ids(ids)])
    }

    static func mySubmissions(gameId: UUID) async throws -> [Submission] {
        try await GoAPI.get("/v1/games/\(id(gameId))/my-submissions")
    }

    static func rewards(gameId: UUID) async throws -> [Reward] {
        try await GoAPI.get("/v1/games/\(id(gameId))/rewards")
    }

    /// F-22: leave a game (not possible for its host).
    static func leaveGame(gameId: UUID) async throws {
        try await GoAPI.write("DELETE", "/v1/games/\(id(gameId))/membership")
    }

    // MARK: Photos

    /// Where to upload a new photo: the server picks the path and signs a one-time upload URL if
    /// the caller may upload it (`proof`: a participant of the game; `hint_media`: its staff;
    /// `avatar`: anyone, own folder).
    struct UploadSlot: Decodable, Sendable {
        let bucket: String
        let path: String
        let uploadUrl: URL
    }

    static func newUpload(kind: String, gameId: UUID? = nil) async throws -> UploadSlot {
        try await GoAPI.write("POST", "/v1/uploads",
                              body: JSONBody(fields: ["kind": .string(kind), "game_id": gameId.map { .string(id($0)) } ?? .null]),
                              as: UploadSlot.self)
    }

    /// PUTs a JPEG to a signed upload URL. "Already exists" counts as success, so a retry after a lost
    /// response is idempotent.
    static func upload(_ slot: UploadSlot, data: Data) async throws {
        var req = URLRequest(url: slot.uploadUrl)
        req.httpMethod = "PUT"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let (body, resp) = try await GoAPI.session.upload(for: req, from: data)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || status == 409 { return }
        if String(data: body, encoding: .utf8)?.localizedCaseInsensitiveContains("exists") == true { return }
        throw GoAPI.Failure(code: "upload_failed", status: status)
    }

    /// A short-lived URL for a private photo (`proofs`, `hint-media`) the caller may see.
    static func fileURL(bucket: String, path: String) async throws -> URL {
        struct R: Decodable { let url: URL }
        return try await GoAPI.get("/v1/file-url", query: ["bucket": bucket, "path": path], as: R.self).url
    }

    // MARK: Profile / account

    static func myProfile() async throws -> Profile {
        try await GoAPI.get("/v1/me/profile")
    }

    static func updateDisplayName(_ name: String) async throws {
        try await GoAPI.write("PATCH", "/v1/me/profile", body: ["display_name": name])
    }

    /// F-02: uploads a square JPEG to the public `avatars` bucket (a fresh name each time, so caches
    /// never serve the old picture) and points the profile at it.
    static func updateAvatar(jpeg: Data) async throws -> String {
        let slot = try await newUpload(kind: "avatar")
        try await upload(slot, data: jpeg)
        try await GoAPI.write("PATCH", "/v1/me/profile", body: ["avatar_path": slot.path])
        return slot.path
    }

    static func removeAvatar() async throws {
        try await GoAPI.write("PATCH", "/v1/me/profile", body: JSONBody(fields: ["avatar_path": .null]))
    }

    /// `avatars` is a public bucket, so no signed URL is needed.
    static func avatarURL(path: String) -> URL? {
        AppConfig.supabaseURL?.appending(path: "storage/v1/object/public/avatars/" + path)
    }

    /// N-11 / App Store: delete the account, then sign out.
    static func deleteMyAccount() async throws {
        try await GoAPI.write("DELETE", "/v1/me")
        try? await Supa.client.auth.signOut(scope: .local)
    }

    static func registerDeviceToken(_ token: String) async throws {
        try await GoAPI.write("POST", "/v1/me/device-tokens", body: ["token": token])
    }
}
