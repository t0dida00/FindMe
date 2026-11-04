import Foundation
import Supabase

/// Host / co-host operations (F-03..F-15). Direct table writes are limited by RLS to staff and,
/// for hints/hint_items, to games still in draft/scheduled.
extension API {
    static func createGame(_ form: GameForm) async throws -> Game {
        let uid = try requireUser()
        return try await db.from("games").insert(NewGame(hostId: uid, form: form))
            .select().single().execute().value
    }

    static func updateGame(id: UUID, form: GameForm) async throws {
        try await db.from("games").update(GameWrite(form: form)).eq("id", value: id).execute()
    }

    /// Only drafts can be deleted (RLS games_delete).
    static func deleteDraftGame(id: UUID) async throws {
        try await db.from("games").delete().eq("id", value: id).execute()
    }

    static func startGame(id: UUID) async throws {
        try await db.rpc("start_game", params: ["p_game_id": id]).execute()
    }

    static func scheduleGame(id: UUID, at date: Date) async throws {
        struct P: Encodable { let pGameId: UUID; let pStartsAt: Date }
        try await db.rpc("schedule_game", params: P(pGameId: id, pStartsAt: date)).execute()
    }

    static func cancelGame(id: UUID) async throws {
        try await db.rpc("cancel_game", params: ["p_game_id": id]).execute()
    }

    static func setRole(gameId: UUID, userId: UUID, role: ParticipantRole) async throws {
        struct P: Encodable { let pGameId: UUID; let pUserId: UUID; let pRole: ParticipantRole }
        try await db.rpc("set_participant_role", params: P(pGameId: gameId, pUserId: userId, pRole: role)).execute()
    }

    // MARK: Hints

    static func hints(gameId: UUID) async throws -> [HostHint] {
        try await db.from("hints")
            .select("id, game_id, hint_order, title, description, prize, prize_item, answer_lat, answer_lng, activated_at, revealed_at, winner_submission_id")
            .eq("game_id", value: gameId).order("hint_order").execute().value
    }

    static func generateHintCode() async throws -> String {
        try await db.rpc("generate_hint_code").execute().value
    }

    static func createHint(gameId: UUID, order: Int, code: String, lat: Double, lng: Double,
                           prize: Double, prizeItem: String? = nil,
                           title: String?, description: String?) async throws -> UUID {
        struct P: Encodable {
            let pGameId: UUID; let pHintOrder: Int; let pCode: String
            let pAnswerLat: Double; let pAnswerLng: Double; let pPrize: Double; let pTitle: String?
            let pDescription: String?; let pPrizeItem: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: K.self)
                try c.encode(pGameId, forKey: .pGameId); try c.encode(pHintOrder, forKey: .pHintOrder)
                try c.encode(pCode, forKey: .pCode); try c.encode(pAnswerLat, forKey: .pAnswerLat)
                try c.encode(pAnswerLng, forKey: .pAnswerLng); try c.encode(pPrize, forKey: .pPrize)
                try c.encode(pTitle, forKey: .pTitle); try c.encode(pDescription, forKey: .pDescription)
                // Chỉ gửi khi có: server chưa chạy 20261103001800 vẫn nhận lời gọi cũ (8 tham số).
                try c.encodeIfPresent(pPrizeItem, forKey: .pPrizeItem)
            }
            enum K: String, CodingKey { case pGameId, pHintOrder, pCode, pAnswerLat, pAnswerLng, pPrize, pTitle, pDescription, pPrizeItem }
        }
        return try await db.rpc("create_hint", params: P(pGameId: gameId, pHintOrder: order, pCode: code,
                                                         pAnswerLat: lat, pAnswerLng: lng, pPrize: prize,
                                                         pTitle: title, pDescription: description,
                                                         pPrizeItem: prizeItem?.trimmingCharacters(in: .whitespacesAndNewlines))).execute().value
    }

    static func setHintCode(hintId: UUID, code: String) async throws {
        struct P: Encodable { let pHintId: UUID; let pCode: String }
        try await db.rpc("set_hint_code", params: P(pHintId: hintId, pCode: code)).execute()
    }

    /// Mã gốc của hint (bảng hint_codes, chỉ staff đọc được). nil với hint tạo trước khi app lưu mã gốc.
    static func hintCode(hintId: UUID) async throws -> String? {
        struct Row: Decodable { let code: String }
        let rows: [Row] = try await db.from("hint_codes").select("code").eq("hint_id", value: hintId)
            .limit(1).execute().value
        return rows.first?.code
    }

    /// Mã gốc của nhiều hint cùng lúc (danh sách hint ở tab Quản lý). Hint không có mã gốc thì không có trong kết quả.
    static func hintCodes(hintIds: [UUID]) async throws -> [UUID: String] {
        guard !hintIds.isEmpty else { return [:] }
        struct Row: Decodable { let hintId: UUID; let code: String }
        let rows: [Row] = try await db.from("hint_codes").select("hint_id,code")
            .in("hint_id", values: hintIds.map(\.uuidString)).execute().value
        return Dictionary(rows.map { ($0.hintId, $0.code) }, uniquingKeysWith: { a, _ in a })
    }

    struct HintPatch: Encodable, Sendable {
        var title: String?
        var description: String?
        var prize: Double
        /// Hiện vật; nil = tiền (luôn gửi, null xóa tên cũ).
        var prizeItem: String? = nil
        /// nil = không gửi vị trí. Khi game đã bắt đầu, server chặn mọi thay đổi vị trí
        /// ('hint_location_locked'), nên chỉ gửi khi vị trí thật sự đổi và game còn sửa được.
        var answerLat: Double?
        var answerLng: Double?
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(title, forKey: .title); try c.encode(description, forKey: .description)
            try c.encode(prize, forKey: .prize)
            try c.encode(prizeItem?.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .prizeItem)
            try c.encodeIfPresent(answerLat, forKey: .answerLat); try c.encodeIfPresent(answerLng, forKey: .answerLng)
        }
        enum K: String, CodingKey { case title, description, prize, prizeItem, answerLat, answerLng }
    }

    static func updateHint(id: UUID, patch: HintPatch) async throws {
        try await db.from("hints").update(patch).eq("id", value: id).execute()
    }

    static func setHintOrder(id: UUID, order: Int) async throws {
        try await db.from("hints").update(["hint_order": order]).eq("id", value: id).execute()
    }

    /// Swap two hints' order. `unique (game_id, hint_order)` is not deferrable, so park one on a temp slot.
    static func swapHintOrder(_ a: HostHint, _ b: HostHint) async throws {
        let temp = 100_000 + Int.random(in: 0..<100_000)
        try await setHintOrder(id: a.id, order: temp)
        try await setHintOrder(id: b.id, order: a.hintOrder)
        try await setHintOrder(id: a.id, order: b.hintOrder)
    }

    static func deleteHint(id: UUID) async throws {
        try await db.from("hints").delete().eq("id", value: id).execute()
    }

    // MARK: Hint items

    static func hintItems(hintId: UUID) async throws -> [HostHintItem] {
        try await db.from("hint_items").select().eq("hint_id", value: hintId)
            .order("item_order").execute().value
    }

    static func insertHintItem(_ draft: HintItemDraft) async throws {
        try await db.from("hint_items").insert(draft).execute()
    }

    static func updateHintItem(id: UUID, draft: HintItemDraft) async throws {
        try await db.from("hint_items").update(draft).eq("id", value: id).execute()
    }

    static func setItemOrder(id: UUID, order: Int) async throws {
        try await db.from("hint_items").update(["item_order": order]).eq("id", value: id).execute()
    }

    static func deleteHintItem(id: UUID) async throws {
        try await db.from("hint_items").delete().eq("id", value: id).execute()
    }

    /// Host hint media: hint-media/{game_id}/{uuid}.jpg (RLS: staff of that game).
    static func uploadHintImage(gameId: UUID, data: Data) async throws -> String {
        let path = "\(gameId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await db.storage.from("hint-media")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        return path
    }

    // MARK: Live review

    /// Open submissions (reserved = waiting for photo, pending = waiting for review).
    static func openSubmissions(gameId: UUID) async throws -> [Submission] {
        try await db.from("submissions").select().eq("game_id", value: gameId)
            .in("status", values: ["reserved", "pending"])
            .order("reserved_at").execute().value
    }

    static func recentSubmissions(gameId: UUID, limit: Int = 30) async throws -> [Submission] {
        try await db.from("submissions").select().eq("game_id", value: gameId)
            .in("status", values: ["approved", "denied", "expired"])
            .order("reserved_at", ascending: false).limit(limit).execute().value
    }

    static func reviewSubmission(id: UUID, approve: Bool, reason: String?) async throws {
        struct P: Encodable {
            let pSubmissionId: UUID; let pApprove: Bool; let pReason: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: K.self)
                try c.encode(pSubmissionId, forKey: .pSubmissionId)
                try c.encode(pApprove, forKey: .pApprove)
                try c.encode(pReason, forKey: .pReason)
            }
            enum K: String, CodingKey { case pSubmissionId, pApprove, pReason }
        }
        try await db.rpc("review_submission", params: P(pSubmissionId: id, pApprove: approve, pReason: reason)).execute()
    }

    static func events(gameId: UUID, limit: Int = 200) async throws -> [GameEvent] {
        try await db.from("game_events").select().eq("game_id", value: gameId)
            .order("id", ascending: false).limit(limit).execute().value
    }

    static func setPayout(rewardId: UUID, paid: Bool) async throws {
        try await db.from("rewards").update(["payout_status": paid ? "paid" : "unpaid"])
            .eq("id", value: rewardId).execute()
    }
}
