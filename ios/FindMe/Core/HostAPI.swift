import Foundation

/// Host / co-host operations (F-03..F-15). The server checks who may change what (staff only; hints
/// and blocks only while the game allows it).
extension API {
    static func createGame(_ form: GameForm) async throws -> Game {
        try await GoAPI.write("POST", "/v1/games", body: GameWrite(form: form), as: Game.self)
    }

    static func updateGame(id: UUID, form: GameForm) async throws {
        try await GoAPI.write("PATCH", "/v1/games/\(id.uuidString.lowercased())", body: GameWrite(form: form))
    }

    /// Only drafts can be deleted (by their host).
    static func deleteDraftGame(id: UUID) async throws {
        try await GoAPI.write("DELETE", "/v1/games/\(id.uuidString.lowercased())")
    }

    static func startGame(id: UUID) async throws {
        try await GoAPI.write("POST", "/v1/games/\(id.uuidString.lowercased())/start")
    }

    static func scheduleGame(id: UUID, at date: Date) async throws {
        struct B: Encodable { let startsAt: Date }
        try await GoAPI.write("POST", "/v1/games/\(id.uuidString.lowercased())/schedule", body: B(startsAt: date))
    }

    static func cancelGame(id: UUID) async throws {
        try await GoAPI.write("POST", "/v1/games/\(id.uuidString.lowercased())/cancel")
    }

    static func setRole(gameId: UUID, userId: UUID, role: ParticipantRole) async throws {
        try await GoAPI.write("PUT", "/v1/games/\(gameId.uuidString.lowercased())/participants/\(userId.uuidString.lowercased())/role", body: ["role": role.rawValue])
    }

    // MARK: Hints

    static func hints(gameId: UUID) async throws -> [HostHint] {
        try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/hints", as: [HostHint].self)
    }

    static func generateHintCode() async throws -> String {
        try await GoAPI.get("/v1/hint-codes/new", as: String.self)
    }

    static func createHint(gameId: UUID, order: Int, code: String, lat: Double, lng: Double,
                           prize: Double, prizeItem: String? = nil,
                           title: String?, description: String?) async throws -> UUID {
        struct B: Encodable {
            let hintOrder: Int; let code: String; let answerLat: Double; let answerLng: Double
            let prize: Double; let prizeItem: String?; let title: String?; let description: String?
        }
        let item = prizeItem?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await GoAPI.write("POST", "/v1/games/\(gameId.uuidString.lowercased())/hints",
                                     body: B(hintOrder: order, code: code, answerLat: lat, answerLng: lng, prize: prize,
                                             prizeItem: item, title: title, description: description), as: UUID.self)
    }

    static func setHintCode(hintId: UUID, code: String) async throws {
        try await GoAPI.write("PUT", "/v1/hints/\(hintId.uuidString.lowercased())/code", body: ["code": code])
    }

    /// Mã gốc của hint (chỉ staff xem được). nil với hint tạo trước khi app lưu mã gốc.
    static func hintCode(hintId: UUID) async throws -> String? {
        try await hintCodes(hintIds: [hintId])[hintId]
    }

    /// Mã gốc của nhiều hint cùng lúc (danh sách hint ở tab Quản lý). Hint không có mã gốc thì không có trong kết quả.
    static func hintCodes(hintIds: [UUID]) async throws -> [UUID: String] {
        guard !hintIds.isEmpty else { return [:] }
        struct Row: Decodable { let hintId: UUID; let code: String }
        let rows = try await GoAPI.get("/v1/hint-codes", query: ["hint_ids": GoAPI.ids(hintIds)], as: [Row].self)
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
        try await GoAPI.write("PATCH", "/v1/hints/\(id.uuidString.lowercased())", body: patch)
    }


    /// Swap two hints' order (before the game starts).
    static func swapHintOrder(_ a: HostHint, _ b: HostHint) async throws {
        try await GoAPI.write("POST", "/v1/hints/swap", body: ["a": a.id, "b": b.id])
    }

    static func deleteHint(id: UUID) async throws {
        try await GoAPI.write("DELETE", "/v1/hints/\(id.uuidString.lowercased())")
    }

    // MARK: Hint items

    static func hintItems(hintId: UUID) async throws -> [HostHintItem] {
        try await GoAPI.get("/v1/hints/\(hintId.uuidString.lowercased())/items", as: [HostHintItem].self)
    }

    static func insertHintItem(_ draft: HintItemDraft) async throws {
        try await GoAPI.write("POST", "/v1/hints/\(draft.hintId.uuidString.lowercased())/items", body: draft.goFields)
    }

    static func updateHintItem(id: UUID, draft: HintItemDraft) async throws {
        try await GoAPI.write("PATCH", "/v1/hint-items/\(id.uuidString.lowercased())", body: draft.goFields)
    }

    static func setItemOrder(id: UUID, order: Int) async throws {
        try await GoAPI.write("PATCH", "/v1/hint-items/\(id.uuidString.lowercased())", body: ["item_order": order])
    }

    static func deleteHintItem(id: UUID) async throws {
        try await GoAPI.write("DELETE", "/v1/hint-items/\(id.uuidString.lowercased())")
    }

    /// Host hint media: hint-media/{game_id}/{uuid}.jpg (staff of that game).
    static func uploadHintImage(gameId: UUID, data: Data) async throws -> String {
        let slot = try await newUpload(kind: "hint_media", gameId: gameId)
        try await upload(slot, data: data)
        return slot.path
    }

    // MARK: Live review

    /// Open submissions (reserved = waiting for photo, pending = waiting for review).
    static func openSubmissions(gameId: UUID) async throws -> [Submission] {
        try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/submissions", query: ["status": "open"], as: [Submission].self)
    }

    static func recentSubmissions(gameId: UUID, limit: Int = 30) async throws -> [Submission] {
        try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/submissions", query: ["status": "recent", "limit": "\(limit)"], as: [Submission].self)
    }

    static func reviewSubmission(id: UUID, approve: Bool, reason: String?) async throws {
        try await GoAPI.write("POST", "/v1/submissions/\(id.uuidString.lowercased())/review",
                              body: JSONBody(fields: ["approve": .bool(approve), "reason": reason.map(JSONValue.string) ?? .null]))
    }

    static func events(gameId: UUID, limit: Int = 200) async throws -> [GameEvent] {
        try await GoAPI.get("/v1/games/\(gameId.uuidString.lowercased())/events", query: ["limit": "\(limit)"], as: [GameEvent].self)
    }

    static func setPayout(rewardId: UUID, paid: Bool) async throws {
        try await GoAPI.write("PUT", "/v1/rewards/\(rewardId.uuidString.lowercased())/payout", body: ["paid": paid])
    }
}
