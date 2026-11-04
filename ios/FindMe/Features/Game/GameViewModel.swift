import Foundation
import Observation
import UIKit

/// Owns all state of one opened game. Every Realtime INSERT on `game_events` (filtered by game_id),
/// every return to foreground and every network reconnect triggers a refetch (N-05, N-12).
@MainActor @Observable
final class GameViewModel {
    let gameId: UUID

    // Shared
    private(set) var game: Game?
    private(set) var myRole: ParticipantRole?
    private(set) var revealedAnswers: [RevealedAnswer] = []
    private(set) var leaderboard: [LeaderboardEntry] = []
    private(set) var rewards: [Reward] = []
    private(set) var participants: [Participant] = []
    private(set) var names: [UUID: String] = [:]
    private(set) var loadError: String?
    private(set) var isLoaded = false
    var banner: String?
    /// Icon của banner: cờ (sự kiện cuộc săn) hoặc dấu tích (đã lưu thành công).
    private(set) var bannerIsSuccess = false
    private(set) var hapticTick = 0
    private(set) var realtimeConnected = false

    // Player
    private(set) var hints: [PlayerHint] = []
    private(set) var nextRevealAt: Date?
    private(set) var codeStatus: CodeStatus?
    private(set) var codeState: MyCodeState?
    private(set) var mySubmissions: [Submission] = []
    var deniedNotice: String?

    // Staff
    private(set) var hostHints: [HostHint] = []
    private(set) var openSubmissions: [Submission] = []
    private(set) var recentSubmissions: [Submission] = []
    private(set) var events: [GameEvent] = []

    private var refreshing = false
    private var refreshAgain = false
    private var bannerTask: Task<Void, Never>?
    private var lastSeenSolved: Set<Int> = []

    init(gameId: UUID) { self.gameId = gameId }

    var isStaff: Bool { myRole?.isStaff ?? false }
    var isHost: Bool { myRole == .host }
    var myId: UUID? { Supa.currentUserId }

    var currentHint: PlayerHint? {
        guard let order = game?.currentHintOrder else { return nil }
        return hints.first { $0.order == order }
    }

    var solvedHints: [PlayerHint] { hints.filter(\.solved).reversed() }

    /// Latest own submission for the current hint.
    var currentSubmission: Submission? {
        guard let hint = currentHint else { return nil }
        return mySubmissions.first { $0.hintId == hint.id }
    }

    func name(for id: UUID) -> String { names[id] ?? String(localized: "Người chơi") }

    // MARK: Lifecycle

    /// Loads the game, then follows its live events until the surrounding task is cancelled.
    func run() async {
        await refresh()
        await runGoStream()
    }

    // MARK: Realtime (Server-Sent Events from the server)

    /// Listens to GET /v1/games/{id}/stream until the task is cancelled: reconnects with
    /// Last-Event-ID (the server replays missed events), refetches on `resync` and after a reconnect,
    /// and stops for good when the server says we are no longer a member.
    private func runGoStream() async {
        let path = "/v1/games/\(gameId.uuidString.lowercased())/stream"
        var lastID: String?
        var backoff = 1.0
        var connectedBefore = false
        while !Task.isCancelled {
            do {
                var req = try await GoAPI.request("GET", path)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let lastID { req.setValue(lastID, forHTTPHeaderField: "Last-Event-ID") }
                let (bytes, resp) = try await GoAPI.streamSession.bytes(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 403 || status == 404 { setRealtime(false); return } // not a member
                guard status == 200 else { throw URLError(.badServerResponse) }
                setRealtime(true)
                backoff = 1
                if connectedBefore { await refresh() } // events may have been missed while offline
                connectedBefore = true
                // `lines` drops blank lines, so an event is complete at its `data:` line (the server
                // always writes data last).
                var event = "message", id: String?
                for try await line in bytes.lines {
                    if line.hasPrefix("id:") {
                        id = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("event:") {
                        event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        switch event {
                        case "game_event":
                            if let info = Self.eventInfo(json: data) { await handle(info) }
                            if let id { lastID = id }
                        case "resync":
                            await refresh()
                        case "bye":
                            if data.contains("not_a_member") { setRealtime(false); return }
                        default: break
                        }
                        event = "message"; id = nil
                    }
                }
            } catch {
                if Task.isCancelled { break }
                print("Go stream error: \(error)")
            }
            setRealtime(false)
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
        setRealtime(false)
    }

    /// A game_events row (JSON) → the fields `handle` uses.
    nonisolated static func eventInfo(json: String) -> EventInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        let p = obj["payload"] as? [String: Any] ?? [:]
        return EventInfo(type: type,
                         hintOrder: (p["hint_order"] as? NSNumber)?.intValue ?? (p["hint_order"] as? String).flatMap(Int.init),
                         winnerName: p["winner_name"] as? String,
                         userId: (p["user_id"] as? String).flatMap(UUID.init(uuidString:)),
                         reason: p["reason"] as? String)
    }

    struct EventInfo: Sendable {
        let type: String
        let hintOrder: Int?
        let winnerName: String?
        let userId: UUID?
        let reason: String?
    }

    private func setRealtime(_ connected: Bool) { realtimeConnected = connected }

    private func handle(_ e: EventInfo) async {
        switch e.type {
        case "hint_item_revealed", "hint_activated", "game_started":
            hapticTick += 1
        case "hint_solved":
            if let order = e.hintOrder {
                lastSeenSolved.insert(order)
                let who = e.winnerName ?? String(localized: "Một người chơi")
                showBanner(String(localized: "\(who) đã tìm ra Hint \(order)"))
            }
        case "proof_denied":
            if e.userId == myId {
                deniedNotice = e.reason.map { String(localized: "Mã của bạn bị từ chối: \($0)") }
                    ?? String(localized: "Mã của bạn bị từ chối.")
            }
        default:
            break
        }
        await refresh()
        // Add the solve time to the banner once answers are loaded (F-26).
        if e.type == "hint_solved", let order = e.hintOrder,
           let answer = revealedAnswers.first(where: { $0.hintOrder == order }), let secs = answer.secondsToSolve {
            showBanner(String(localized: "\(answer.winnerName) đã tìm ra Hint \(order) sau \(Fmt.duration(seconds: secs))"))
        }
    }

    func showBanner(_ text: String, success: Bool = false) {
        banner = text
        bannerIsSuccess = success
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(success ? 3 : 6))
            if !Task.isCancelled { banner = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: Refresh (coalesced)

    func refresh() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            await load()
        } while refreshAgain
    }

    private func load() async {
        do {
            let gid = gameId
            async let gameReq = API.game(id: gid)
            async let partsReq = API.participants(gameId: gid)
            let (g, parts) = try await (gameReq, partsReq)
            game = g
            participants = parts
            myRole = parts.first { $0.userId == myId }?.role ?? (g.hostId == myId ? .host : nil)

            async let answersReq = API.revealedAnswers(gameId: gid)
            async let boardReq = API.leaderboard(gameId: gid)
            async let rewardsReq = API.rewards(gameId: gid)
            async let itemsReq = API.hintItems(gameId: gid)
            (revealedAnswers, leaderboard, rewards) = try await (answersReq, boardReq, rewardsReq)
            var grouped = PlayerHint.group(try await itemsReq)
            // Mọi khối của hint hiện tại còn hẹn giờ → get_hint_items không trả hint đó; lấy riêng
            // để người chơi vẫn nhập mã được.
            if g.status == .live, let cur = try await API.currentHint(gameId: gid),
               !grouped.contains(where: { $0.id == cur.hintId }) {
                grouped.append(PlayerHint(id: cur.hintId, order: cur.hintOrder, title: cur.hintTitle,
                                          description: cur.hintDescription,
                                          prize: cur.prize, prizeItem: cur.prizeItem, activatedAt: cur.activatedAt,
                                          solved: false, items: []))
                grouped.sort { $0.order < $1.order }
            }
            hints = grouped

            if g.status == .live {
                async let nextReq = API.nextRevealAt(gameId: gid)
                async let statusReq = API.currentCodeStatus(gameId: gid)
                (nextRevealAt, codeStatus) = try await (nextReq, statusReq)
            } else {
                nextRevealAt = nil
                codeStatus = nil
            }

            events = (try? await API.events(gameId: gid)) ?? events
            if isStaff {
                async let hh = API.hints(gameId: gid)
                async let open = API.openSubmissions(gameId: gid)
                async let recent = API.recentSubmissions(gameId: gid)
                (hostHints, openSubmissions, recentSubmissions) = try await (hh, open, recent)
            } else {
                mySubmissions = try await API.mySubmissions(gameId: gid)
                if g.status == .live, let hint = currentHint {
                    codeState = try? await API.myCodeState(hintId: hint.id)
                } else {
                    codeState = nil
                }
            }

            let missing = Set(parts.map(\.userId)).subtracting(names.keys)
            if !missing.isEmpty {
                for p in try await API.profiles(ids: Array(missing)) { names[p.id] = p.displayName }
            }
            loadError = nil
            isLoaded = true
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            loadError = AppError.message(for: error)
            isLoaded = true
        }
    }

    // MARK: Player actions

    enum RedeemOutcome {
        case reserved(ProofTarget)
        case message(String)
    }

    func redeem(code: String) async -> RedeemOutcome {
        guard let hint = currentHint else {
            return .message(String(localized: "Chưa có hint đang mở."))
        }
        do {
            let r = try await API.redeemCode(hintId: hint.id, code: code)
            if r.ok, let sid = r.submissionId, let deadline = r.uploadDeadline, let prefix = r.uploadPathPrefix {
                await refresh()
                return .reserved(ProofTarget(submissionId: sid, deadline: deadline, pathPrefix: prefix))
            }
            codeState = MyCodeState(attemptsBeforeLock: r.attemptsBeforeLock, lockedUntil: r.lockedUntil)
            switch r.error {
            case "wrong_code":
                if let until = r.lockedUntil {
                    return .message(String(localized: "Sai mã. Bạn bị khóa nhập mã đến \(Fmt.time(until))."))
                }
                let left = r.attemptsBeforeLock ?? 0
                return .message(String(localized: "Sai mã. Còn \(left) lần thử trước khi bị khóa."))
            case "code_entry_locked":
                return .message(String(localized: "Bạn đang bị khóa nhập mã. Hãy đợi hết thời gian đếm ngược."))
            case "code_in_use":
                await refresh()
                return .message(String(localized: "Có người đang xác minh mã này"))
            default:
                return .message(AppError.message(code: r.error ?? "") ?? String(localized: "Không xác định được kết quả."))
            }
        } catch {
            await refresh()
            return .message(AppError.message(for: error))
        }
    }

    /// Restore an in-flight reservation after relaunch (N-12).
    var resumableTarget: ProofTarget? {
        guard let s = currentSubmission, s.status == .reserved, s.uploadDeadline > Date() else { return nil }
        let prefix = "\(s.gameId.uuidString.lowercased())/\(s.userId.uuidString.lowercased())/"
        return ProofTarget(submissionId: s.id, deadline: s.uploadDeadline, pathPrefix: prefix)
    }

    func leave() async throws {
        try await API.leaveGame(gameId: gameId)
    }

    // MARK: Staff actions

    func review(_ submission: Submission, approve: Bool, reason: String?) async throws {
        try await API.reviewSubmission(id: submission.id, approve: approve, reason: reason)
        await refresh()
    }

    func hintOrder(for hintId: UUID) -> Int? { hostHints.first { $0.id == hintId }?.hintOrder }
}

/// A reserved code waiting for its proof photo.
struct ProofTarget: Identifiable, Hashable, Sendable {
    let submissionId: UUID
    let deadline: Date
    let pathPrefix: String
    var id: UUID { submissionId }
}
