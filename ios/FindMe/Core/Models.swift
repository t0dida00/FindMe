import Foundation

// MARK: - Enums (mirror Postgres enums)

enum GameStatus: String, Codable, Sendable, CaseIterable {
    case draft, scheduled, live, completed, cancelled

    var isEditable: Bool { self == .draft || self == .scheduled }
    var isFinished: Bool { self == .completed || self == .cancelled }
}

enum ParticipantRole: String, Codable, Sendable {
    case host, cohost, player
    var isStaff: Bool { self != .player }
}

enum HintItemType: String, Codable, Sendable, CaseIterable {
    case text, image, map
}

enum SubmissionStatus: String, Codable, Sendable {
    case reserved, pending, approved, denied, expired
}

enum CodeStatus: String, Codable, Sendable {
    case open
    case inReview = "in_review"
    case solved
}

enum PayoutStatus: String, Codable, Sendable { case unpaid, paid }
enum RewardKind: String, Codable, Sendable { case milestone, grand }

// MARK: - Tables

struct Game: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let hostId: UUID
    var title: String
    var description: String?
    let status: GameStatus
    let joinCode: String
    var grandPrize: Double
    var currency: String
    /// Giải tổng là hiện vật (tên món quà); nil = tiền (20261103001800_item_prizes.sql).
    var grandPrizeItem: String?
    let currentHintOrder: Int?
    var autoApproveEnabled: Bool
    var autoApproveMinutes: Int
    var uploadWindowSeconds: Int
    var codeFailsBeforeLock: Int
    var codeLockMinutes: Int
    var publicWinnerPhotos: Bool
    /// Fixed at 7 days by the server (20261103000600_player_limit.sql); read-only in the app.
    let proofRetentionDays: Int
    let startsAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    let createdAt: Date?
    // Globe (20261103000400_globe.sql). Optional so the app still decodes rows from an older schema.
    var isPublic: Bool?
    var areaLat: Double?
    var areaLng: Double?
    var areaName: String?
    // 20261103000600_player_limit.sql. Optional for the same reason.
    var maxPlayers: Int?
    /// Công khai và mở cho mọi người (vào không cần mã), 20261103002100_open_join.sql.
    var joinOpen: Bool?
}

/// Editable game fields (F-03 + F-08). Encodes snake_case via the shared encoder.
struct GameForm: Codable, Sendable, Equatable {
    var title: String = ""
    var description: String = ""
    var grandPrize: Double = 0
    var currency: String = "VND"
    /// nil = giải tổng bằng tiền; khác nil (kể cả "" khi đang gõ) = hiện vật.
    var grandPrizeItem: String?
    var autoApproveEnabled: Bool = true
    var autoApproveMinutes: Int = 15
    var uploadWindowSeconds: Int = 60
    var codeFailsBeforeLock: Int = 3
    var codeLockMinutes: Int = 10
    var publicWinnerPhotos: Bool = true
    /// Số người chơi tối đa (quản trò, co-host không tính). Server: 1–50, không thấp hơn số đang có.
    var maxPlayers: Int = GameForm.playerLimit
    /// Globe: hiện trên bản đồ chung; bắt buộc có khu vực (server làm tròn ~1 km).
    var isPublic: Bool = false
    /// Chỉ khi công khai: true = ai cũng vào được không cần mã. Optional để nháp cũ vẫn đọc được.
    var joinOpen: Bool?
    var areaLat: Double?
    var areaLng: Double?
    var areaName: String?

    var isAreaValid: Bool { !isPublic || (areaLat != nil && areaLng != nil) }
    /// Chọn hiện vật thì phải có tên.
    var isPrizeValid: Bool { grandPrizeItem.map { PrizeInput.isValidItem($0) } ?? true }
    /// Giới hạn tiền cho thưởng mốc: nil khi giải tổng là hiện vật (không so được).
    var grandPrizeCap: Double? { grandPrizeItem == nil ? grandPrize : nil }

    static let playerLimit = 50
    /// Ảnh proof luôn được giữ 7 ngày sau khi game kết thúc (cố định ở server).
    static let proofRetentionDays = 7

    init() {}

    init(game: Game) {
        title = game.title
        description = game.description ?? ""
        grandPrize = game.grandPrize
        currency = game.currency
        grandPrizeItem = game.grandPrizeItem
        autoApproveEnabled = game.autoApproveEnabled
        autoApproveMinutes = game.autoApproveMinutes
        uploadWindowSeconds = game.uploadWindowSeconds
        codeFailsBeforeLock = game.codeFailsBeforeLock
        codeLockMinutes = game.codeLockMinutes
        publicWinnerPhotos = game.publicWinnerPhotos
        maxPlayers = game.maxPlayers ?? GameForm.playerLimit
        isPublic = game.isPublic ?? false
        joinOpen = game.joinOpen
        areaLat = game.areaLat
        areaLng = game.areaLng
        areaName = game.areaName
    }
}

struct NewGame: Encodable, Sendable {
    let hostId: UUID
    let form: GameForm

    func encode(to encoder: Encoder) throws {
        try GameWrite(form: form).encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(hostId, forKey: .hostId)
    }
    private enum Keys: String, CodingKey { case hostId }
}

/// Ghi GameForm lên bảng games. Gửi `grand_prize_item` cả khi nil (null) để đổi hiện vật → tiền
/// xóa được tên cũ (mã hóa tự sinh bỏ qua optional nil).
struct GameWrite: Encodable, Sendable {
    let form: GameForm

    func encode(to encoder: Encoder) throws {
        try form.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(form.grandPrizeItem?.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .grandPrizeItem)
        try c.encode(form.isPublic && (form.joinOpen ?? false), forKey: .joinOpen)
    }
    private enum Keys: String, CodingKey { case grandPrizeItem, joinOpen }
}

struct MyGameEntry: Decodable, Identifiable, Sendable, Hashable {
    let role: ParticipantRole
    let joinedAt: Date
    let game: Game
    var id: UUID { game.id }
}

/// get_game_summary (20261103001700_game_summary.sql): số liệu cho card "Game của tôi".
struct GameSummary: Decodable, Sendable, Hashable {
    let hostName: String
    /// 20261103001900_host_avatar.sql; optional cho server cũ.
    let hostAvatarPath: String?
    let playerCount: Int
    let hintCount: Int
    let solvedCount: Int
}

struct Participant: Decodable, Identifiable, Sendable, Hashable {
    let userId: UUID
    let role: ParticipantRole
    let joinedAt: Date
    var id: UUID { userId }
}

struct Profile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
}

/// Staff-only view of `hints` (players never read this table, N-02).
struct HostHint: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let gameId: UUID
    var hintOrder: Int
    var title: String?
    var description: String?
    var prize: Double
    /// Thưởng mốc là hiện vật; nil = tiền.
    var prizeItem: String?
    var answerLat: Double
    var answerLng: Double
    let activatedAt: Date?
    let revealedAt: Date?
    let winnerSubmissionId: UUID?
}

struct HostHintItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let hintId: UUID
    var itemOrder: Int
    var type: HintItemType
    var textContent: String?
    var imagePath: String?
    var mapCenterLat: Double?
    var mapCenterLng: Double?
    var mapRadiusM: Int?
    var revealAfterMinutes: Int?
    let revealAnnouncedAt: Date?
}

struct HintItemDraft: Encodable, Sendable {
    let hintId: UUID
    var itemOrder: Int
    var type: HintItemType
    var textContent: String?
    var imagePath: String?
    var mapRadiusM: Int?
    var revealAfterMinutes: Int?

    // Explicitly encode nulls so an update can clear fields.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hintId, forKey: .hintId)
        try c.encode(itemOrder, forKey: .itemOrder)
        try c.encode(type, forKey: .type)
        try c.encode(textContent, forKey: .textContent)
        try c.encode(imagePath, forKey: .imagePath)
        try c.encode(mapRadiusM, forKey: .mapRadiusM)
        try c.encode(revealAfterMinutes, forKey: .revealAfterMinutes)
    }
    private enum CodingKeys: String, CodingKey {
        case hintId, itemOrder, type, textContent, imagePath, mapRadiusM, revealAfterMinutes
    }
}

struct Submission: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let gameId: UUID
    let hintId: UUID
    let userId: UUID
    let status: SubmissionStatus
    let reservedAt: Date
    let uploadDeadline: Date
    let photoPath: String?
    let uploadedAt: Date?
    let photoPurgedAt: Date?
    let autoApproveAt: Date?
    let reviewedAt: Date?
    let autoApproved: Bool
    let denyReason: String?
}

struct Reward: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let gameId: UUID
    let hintId: UUID
    let kind: RewardKind
    let winnerId: UUID
    let amount: Double
    let currency: String
    /// Hiện vật (tên món quà); nil = tiền.
    var item: String?
    var payoutStatus: PayoutStatus
    let createdAt: Date
}

struct GameEvent: Codable, Identifiable, Sendable, Hashable {
    let id: Int
    let gameId: UUID
    let type: String
    let payload: [String: JSONValue]
    let createdAt: Date
}

// MARK: - RPC results

/// One row of `get_hint_items(p_game_id)`.
struct HintItemRow: Decodable, Sendable, Hashable, Identifiable {
    let hintId: UUID
    let hintOrder: Int
    let hintTitle: String?
    let hintDescription: String?
    let prize: Double
    let prizeItem: String?
    let hintActivatedAt: Date?
    let hintSolved: Bool
    let itemId: UUID
    let itemOrder: Int
    let type: HintItemType
    let textContent: String?
    let imagePath: String?
    let mapCenterLat: Double?
    let mapCenterLng: Double?
    let mapRadiusM: Int?
    var id: UUID { itemId }
}

/// Items grouped per hint for display.
struct PlayerHint: Identifiable, Sendable, Hashable {
    let id: UUID
    let order: Int
    let title: String?
    var description: String? = nil
    let prize: Double
    var prizeItem: String? = nil
    let activatedAt: Date?
    let solved: Bool
    let items: [HintItemRow]

    static func group(_ rows: [HintItemRow]) -> [PlayerHint] {
        let byHint = Dictionary(grouping: rows, by: \.hintId)
        return byHint.values.compactMap { rows -> PlayerHint? in
            guard let f = rows.first else { return nil }
            return PlayerHint(id: f.hintId, order: f.hintOrder, title: f.hintTitle,
                              description: f.hintDescription, prize: f.prize, prizeItem: f.prizeItem,
                              activatedAt: f.hintActivatedAt, solved: f.hintSolved,
                              items: rows.sorted { $0.itemOrder < $1.itemOrder })
        }
        .sorted { $0.order < $1.order }
    }
}

/// `get_current_hint` row.
struct CurrentHintRow: Decodable, Sendable {
    let hintId: UUID
    let hintOrder: Int
    let hintTitle: String?
    let hintDescription: String?
    let prize: Double
    let prizeItem: String?
    let activatedAt: Date?
    let hintCount: Int
}

/// `redeem_code` jsonb result.
struct RedeemResult: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let submissionId: UUID?
    let uploadDeadline: Date?
    let uploadPathPrefix: String?
    let attemptsBeforeLock: Int?
    let lockedUntil: Date?
}

/// `get_my_code_state` jsonb result.
struct MyCodeState: Decodable, Sendable, Equatable {
    let attemptsBeforeLock: Int?
    let lockedUntil: Date?
}

struct RevealedAnswer: Decodable, Sendable, Hashable, Identifiable {
    let hintOrder: Int
    let hintTitle: String?
    let answerLat: Double
    let answerLng: Double
    let winnerId: UUID
    let winnerName: String
    let solvedAt: Date
    let secondsToSolve: Int?
    let winnerPhotoPath: String?
    var id: Int { hintOrder }
}

struct LeaderboardEntry: Decodable, Sendable, Hashable, Identifiable {
    let rank: Int
    let userId: UUID
    let displayName: String
    let milestonesWon: Int
    let totalReward: Double
    let totalSeconds: Int
    var id: UUID { userId }
}

// MARK: - Globe (get_globe_games)

struct GlobeGame: Decodable, Sendable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let status: GameStatus
    let isPublic: Bool
    let areaLat: Double
    let areaLng: Double
    let areaName: String?
    let hostName: String
    let hostAvatarPath: String?
    let playerCount: Int
    let hintCount: Int
    let grandPrize: Double
    let currency: String
    let grandPrizeItem: String?
    /// Mở cho mọi người: hiện nút "Tham gia ngay" thay cho nhập mã.
    let joinOpen: Bool?
    let startsAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    /// nil = không tham gia (chỉ xem được vì game công khai).
    let myRole: ParticipantRole?
}

// MARK: - Global rankings (get_player_rankings / get_host_rankings)

struct PlayerRankingEntry: Decodable, Sendable, Hashable, Identifiable {
    let rank: Int
    let userId: UUID
    let displayName: String
    let avatarPath: String?
    let gamesJoined: Int
    let gamesWon: Int
    let hintsSolved: Int
    var id: UUID { userId }
}

struct HostRankingEntry: Decodable, Sendable, Hashable, Identifiable {
    let rank: Int
    let userId: UUID
    let displayName: String
    let avatarPath: String?
    /// Sao trung bình (1 chữ số thập phân); nil khi chưa có lượt chấm.
    let ratingAvg: Double?
    let ratingCount: Int
    let gamesCreated: Int
    let rewardsGiven: Int
    let rewardsVnd: Double
    var id: UUID { userId }
}

// MARK: - Generic JSON value (for game_events.payload)

enum JSONValue: Codable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
}

// MARK: Profile stats + history (get_my_stats / get_my_history)

struct MyStats: Decodable, Sendable, Hashable {
    struct Prize: Decodable, Sendable, Hashable {
        let currency: String
        let amount: Double
    }
    let gamesPlayed: Int
    let gamesHosted: Int
    let hintsFound: Int
    let gamesWon: Int
    let prizes: [Prize]
    /// Số giải hiện vật đã nhận (optional: server cũ chưa có cột này).
    let itemsWon: Int?
}

struct HistoryEntry: Decodable, Identifiable, Sendable, Hashable {
    let gameId: UUID
    let title: String
    let status: GameStatus
    let role: ParticipantRole
    let playedAt: Date
    let hintCount: Int
    let hintsFound: Int
    let rewardAmount: Double
    let currency: String
    /// Tên các hiện vật đã nhận trong game, nối bằng dấu phẩy.
    let rewardItems: String?
    var id: UUID { gameId }
}
