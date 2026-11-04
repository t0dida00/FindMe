import Foundation
import Supabase

/// Thin wrapper over the Supabase RPCs / RLS-allowed tables defined in
/// supabase/migrations/20261103000000_treasure_hunt.sql and 20261103000100_mvp_additions.sql.
/// Nothing here decides game rules — the server does.
enum API {
    static var db: SupabaseClient { Supa.client }

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

    // MARK: Player RPCs

    /// join_game(p_join_code) -> uuid
    static func joinGame(code: String) async throws -> UUID {
        if GoAPI.isEnabled {
            struct R: Decodable { let gameId: UUID }
            return try await GoAPI.write("POST", "/v1/games/join", body: ["code": code], as: R.self).gameId
        }
        return try await db.rpc("join_game", params: ["p_join_code": code]).execute().value
    }

    /// Vào game công khai "mở cho mọi người" không cần mã (join_open_game).
    static func joinOpenGame(gameId: UUID) async throws -> UUID {
        if GoAPI.isEnabled {
            struct R: Decodable { let gameId: UUID }
            return try JSONCoding.decoder.decode(R.self, from: try await GoAPI.send("POST", "/v1/games/\(gameId.uuidString.lowercased())/join")).gameId
        }
        return try await db.rpc("join_open_game", params: ["p_game_id": gameId]).execute().value
    }

    /// get_hint_items(p_game_id) -> table
    static func hintItems(gameId: UUID) async throws -> [HintItemRow] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/hint-items", as: [HintItemRow].self) }) { return v }
        return try await db.rpc("get_hint_items", params: ["p_game_id": gameId]).execute().value
    }

    /// get_current_hint(p_game_id) -> 0..1 row (works even when no block is visible yet)
    static func currentHint(gameId: UUID) async throws -> CurrentHintRow? {
        if let v = try await GoAPI.tryRead({ try await GoAPI.getOptional("/v1/games/\(gameId.uuidString.lowercased())/current-hint", as: CurrentHintRow.self) }) { return v }
        let rows: [CurrentHintRow] = try await db.rpc("get_current_hint", params: ["p_game_id": gameId]).execute().value
        return rows.first
    }

    /// get_next_reveal_at(p_game_id) -> timestamptz | null
    static func nextRevealAt(gameId: UUID) async throws -> Date? {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/next-reveal", as: Date?.self) }) { return v }
        return try await db.rpc("get_next_reveal_at", params: ["p_game_id": gameId]).execute().value
    }

    /// get_current_code_status(p_game_id) -> 'open' | 'in_review' | 'solved' | null
    static func currentCodeStatus(gameId: UUID) async throws -> CodeStatus? {
        if let v = try await GoAPI.tryRead({ (try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/code-status", as: String?.self)).flatMap(CodeStatus.init(rawValue:)) }) { return v }
        let raw: String? = try await db.rpc("get_current_code_status", params: ["p_game_id": gameId]).execute().value
        return raw.flatMap(CodeStatus.init(rawValue:))
    }

    /// get_my_code_state(p_hint_id) -> {attempts_before_lock, locked_until}
    static func myCodeState(hintId: UUID) async throws -> MyCodeState {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/hints/\(hintId.uuidString.lowercased())/my-code-state", as: MyCodeState.self) }) { return v }
        return try await db.rpc("get_my_code_state", params: ["p_hint_id": hintId]).execute().value
    }

    /// redeem_code(p_hint_id, p_code) -> jsonb
    static func redeemCode(hintId: UUID, code: String) async throws -> RedeemResult {
        if GoAPI.isEnabled {
            return try await GoAPI.write("POST", "/v1/hints/\(hintId.uuidString.lowercased())/redeem", body: ["code": code], as: RedeemResult.self)
        }
        struct P: Encodable { let pHintId: UUID; let pCode: String }
        return try await db.rpc("redeem_code", params: P(pHintId: hintId, pCode: code)).execute().value
    }

    /// attach_photo(p_submission_id, p_photo_path) -> void
    static func attachPhoto(submissionId: UUID, path: String) async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("POST", "/v1/submissions/\(submissionId.uuidString.lowercased())/photo", body: ["path": path]) }
        struct P: Encodable { let pSubmissionId: UUID; let pPhotoPath: String }
        try await db.rpc("attach_photo", params: P(pSubmissionId: submissionId, pPhotoPath: path)).execute()
    }

    static func revealedAnswers(gameId: UUID) async throws -> [RevealedAnswer] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/revealed-answers", as: [RevealedAnswer].self) }) { return v }
        return try await db.rpc("get_revealed_answers", params: ["p_game_id": gameId]).execute().value
    }

    static func leaderboard(gameId: UUID) async throws -> [LeaderboardEntry] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/leaderboard", as: [LeaderboardEntry].self) }) { return v }
        return try await db.rpc("get_leaderboard", params: ["p_game_id": gameId]).execute().value
    }

    // MARK: Globe (20261103000400_globe.sql)

    /// Public games (not draft/cancelled) + my own games that have an area. Never includes join codes.
    static func globeGames() async throws -> [GlobeGame] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/globe", as: [GlobeGame].self) }) { return v }
        return try await db.rpc("get_globe_games").execute().value
    }

    // MARK: Global rankings + host rating (20261103000300_rankings.sql)

    /// Top `limit` + my own row if I'm outside the top.
    static func playerRankings(limit: Int = 100) async throws -> [PlayerRankingEntry] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/rankings/players", query: ["limit": "\(limit)"], as: [PlayerRankingEntry].self) }) { return v }
        return try await db.rpc("get_player_rankings", params: ["p_limit": limit]).execute().value
    }

    static func hostRankings(limit: Int = 100) async throws -> [HostRankingEntry] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/rankings/hosts", query: ["limit": "\(limit)"], as: [HostRankingEntry].self) }) { return v }
        return try await db.rpc("get_host_rankings", params: ["p_limit": limit]).execute().value
    }

    // MARK: Profile stats + history (20261103000900_my_stats.sql)

    static func myStats() async throws -> MyStats? {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/me/stats", as: MyStats?.self) }) { return v }
        let rows: [MyStats] = try await db.rpc("get_my_stats").execute().value
        return rows.first
    }

    static func myHistory(limit: Int = 50) async throws -> [HistoryEntry] {
        struct Items: Decodable { let items: [HistoryEntry] }
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/me/history", query: ["limit": "\(limit)"], as: Items.self).items }) { return v }
        return try await db.rpc("get_my_history", params: ["p_limit": limit]).execute().value
    }

    /// rate_host(p_game_id, p_stars): players only, after the game is completed/cancelled. Re-rating overwrites.
    static func rateHost(gameId: UUID, stars: Int) async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("PUT", "/v1/games/\(gameId.uuidString.lowercased())/rating", body: ["stars": stars]) }
        struct P: Encodable { let pGameId: UUID; let pStars: Int }
        try await db.rpc("rate_host", params: P(pGameId: gameId, pStars: stars)).execute()
    }

    static func myHostRating(gameId: UUID) async throws -> Int? {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/my-rating", as: Int?.self) }) { return v }
        return try await db.rpc("get_my_host_rating", params: ["p_game_id": gameId]).execute().value
    }

    // MARK: Tables (RLS)

    static func game(id: UUID) async throws -> Game {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(id.uuidString.lowercased())", as: Game.self) }) { return v }
        return try await db.from("games").select().eq("id", value: id).single().execute().value
    }

    static func myGames() async throws -> [MyGameEntry] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/me/games", as: [MyGameEntry].self) }) { return v }
        let uid = try requireUser()
        return try await db.from("game_participants")
            .select("role, joined_at, game:games(*)")
            .eq("user_id", value: uid)
            .order("joined_at", ascending: false)
            .execute().value
    }

    /// Tên quản trò, số người chơi, x/y hint đã giải (chỉ thành viên của game).
    static func gameSummary(gameId: UUID) async throws -> GameSummary? {
        if let v = try await GoAPI.tryRead({ try await GoAPI.getOptional("/v1/games/\(gameId.uuidString.lowercased())/summary", as: GameSummary.self) }) { return v }
        let rows: [GameSummary] = try await db.rpc("get_game_summary", params: ["p_game_id": gameId]).execute().value
        return rows.first
    }

    static func participants(gameId: UUID) async throws -> [Participant] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/participants", as: [Participant].self) }) { return v }
        return try await db.from("game_participants").select("user_id, role, joined_at")
            .eq("game_id", value: gameId).order("joined_at").execute().value
    }

    static func profiles(ids: [UUID]) async throws -> [Profile] {
        if !ids.isEmpty, let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/profiles", query: ["ids": GoAPI.ids(ids)], as: [Profile].self) }) { return v }
        guard !ids.isEmpty else { return [] }
        return try await db.from("profiles").select("id, display_name, avatar_path")
            .in("id", values: ids.map(\.uuidString)).execute().value
    }

    /// Own submissions (RLS: user_id = auth.uid() or staff).
    static func mySubmissions(gameId: UUID) async throws -> [Submission] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/my-submissions", as: [Submission].self) }) { return v }
        let uid = try requireUser()
        return try await db.from("submissions").select()
            .eq("game_id", value: gameId).eq("user_id", value: uid)
            .order("reserved_at", ascending: false).execute().value
    }

    static func rewards(gameId: UUID) async throws -> [Reward] {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/rewards", as: [Reward].self) }) { return v }
        return try await db.from("rewards").select().eq("game_id", value: gameId)
            .order("created_at").execute().value
    }

    /// F-22: leave = delete own game_participants row (RLS forbids it for the host).
    static func leaveGame(gameId: UUID) async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("DELETE", "/v1/games/\(gameId.uuidString.lowercased())/membership") }
        let uid = try requireUser()
        try await db.from("game_participants").delete()
            .eq("game_id", value: gameId).eq("user_id", value: uid).execute()
    }

    // MARK: Storage

    /// Uploads a proof JPEG to `proofs/<prefix><uuid>.jpg`. Treats "already exists" as success, so a retry
    /// after a lost response is idempotent.
    static func uploadProof(path: String, data: Data) async throws {
        do {
            _ = try await db.storage.from("proofs")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch let e as StorageError where e.statusCode == "409" || e.message.localizedCaseInsensitiveContains("exists") {
            return
        }
    }

    // MARK: Profile / account

    static func myProfile() async throws -> Profile {
        if let v = try await GoAPI.tryRead({ try await GoAPI.get("/v1/me/profile", as: Profile.self) }) { return v }
        let uid = try requireUser()
        return try await db.from("profiles").select("id, display_name, avatar_path")
            .eq("id", value: uid).single().execute().value
    }

    static func updateDisplayName(_ name: String) async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("PATCH", "/v1/me/profile", body: ["display_name": name]) }
        let uid = try requireUser()
        try await db.from("profiles").update(["display_name": name]).eq("id", value: uid).execute()
    }

    /// F-02: uploads a square JPEG to the public `avatars` bucket (`<uid>/<uuid>.jpg`, unique name so
    /// CDN/AsyncImage caches never serve the old picture) and points `profiles.avatar_path` at it.
    static func updateAvatar(jpeg: Data) async throws -> String {
        let uid = try requireUser()
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await db.storage.from("avatars")
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        if GoAPI.isEnabled {
            try await GoAPI.write("PATCH", "/v1/me/profile", body: ["avatar_path": path])
        } else {
            try await db.from("profiles").update(["avatar_path": path]).eq("id", value: uid).execute()
        }
        return path
    }

    static func removeAvatar() async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("PATCH", "/v1/me/profile", body: JSONBody(fields: ["avatar_path": .null])) }
        let uid = try requireUser()
        try await db.from("profiles").update(["avatar_path": String?.none]).eq("id", value: uid).execute()
    }

    /// `avatars` is a public bucket, so no signed URL is needed.
    static func avatarURL(path: String) -> URL? {
        try? db.storage.from("avatars").getPublicURL(path: path)
    }

    /// N-11 / App Store: delete_my_account() then sign out.
    static func deleteMyAccount() async throws {
        if GoAPI.isEnabled {
            try await GoAPI.write("DELETE", "/v1/me")
            try? await db.auth.signOut(scope: .local)
            return
        }
        try await db.rpc("delete_my_account").execute()
        try? await db.auth.signOut(scope: .local)
    }

    static func registerDeviceToken(_ token: String) async throws {
        if GoAPI.isEnabled { return try await GoAPI.write("POST", "/v1/me/device-tokens", body: ["token": token]) }
        try await db.rpc("register_device_token", params: ["p_token": token, "p_platform": "ios"]).execute()
    }
}
