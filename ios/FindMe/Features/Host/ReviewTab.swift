import SwiftUI

/// F-13/F-14: open proofs (reserved = waiting for photo, pending = waiting for review) + recent decisions.
struct ReviewTab: View {
    @Environment(GameViewModel.self) private var vm

    var body: some View {
        let pending = vm.openSubmissions.filter { $0.status == .pending }
        let reserved = vm.openSubmissions.filter { $0.status == .reserved }
        List { ThemedRows {
            if vm.game?.status != .live {
                Text("Duyệt mã chỉ diễn ra khi game đang chạy.").foregroundStyle(.secondary)
            }
            Section("Chờ duyệt (\(pending.count))") {
                if pending.isEmpty { Text("Không có mã nào chờ duyệt.").foregroundStyle(.secondary) }
                ForEach(pending) { s in
                    NavigationLink { ReviewDetailView(submissionId: s.id).fmTabBarInset() } label: { SubmissionRow(submission: s) }
                }
            }
            if !reserved.isEmpty {
                Section("Đang chờ ảnh") {
                    ForEach(reserved) { s in SubmissionRow(submission: s) }
                }
            }
            if !vm.recentSubmissions.isEmpty {
                Section("Gần đây") {
                    ForEach(vm.recentSubmissions) { s in
                        NavigationLink { ReviewDetailView(submissionId: s.id).fmTabBarInset() } label: { SubmissionRow(submission: s) }
                    }
                }
            }
        } }.fmScreen()
        .refreshable { await vm.refresh() }
    }
}

struct SubmissionRow: View {
    @Environment(GameViewModel.self) private var vm
    let submission: Submission

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vm.name(for: submission.userId)).font(.headline)
                Spacer()
                StatusChip(text: submission.status.label, color: submission.status.color)
            }
            HStack(spacing: 6) {
                if let order = vm.hintOrder(for: submission.hintId) { Text("Hint \(order)") }
                Text("·")
                Text("Nhập mã lúc \(Fmt.time(submission.reservedAt))")
            }
            .font(.caption).foregroundStyle(.secondary)
            switch submission.status {
            case .reserved:
                HStack { Text("Hạn chụp ảnh"); CountdownText(until: submission.uploadDeadline) }.font(.caption.bold())
            case .pending:
                if let at = submission.autoApproveAt {
                    HStack { Text("Tự duyệt sau"); CountdownText(until: at) }.font(.caption.bold()).foregroundStyle(.fmWarning)
                }
            default:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReviewDetailView: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let submissionId: UUID
    @State private var reason = ""
    @State private var showDeny = false
    @State private var confirmApprove = false
    @State private var working = false
    @State private var error: String?

    private var submission: Submission? {
        vm.openSubmissions.first { $0.id == submissionId } ?? vm.recentSubmissions.first { $0.id == submissionId }
    }

    var body: some View {
        FMScrollScreen(alignment: .leading) {
            if let s = submission {
                if let path = s.photoPath, s.photoPurgedAt == nil {
                    SignedImage(bucket: "proofs", path: path)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(Text("Ảnh mã"))
                } else {
                    Label("Chưa có ảnh", systemImage: "photo").foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, verticalSpacing: 8) {
                    GridRow { Text("Người nộp").foregroundStyle(.secondary); Text(vm.name(for: s.userId)).bold() }
                    if let order = vm.hintOrder(for: s.hintId) {
                        GridRow { Text("Hint").foregroundStyle(.secondary); Text("\(order)") }
                    }
                    GridRow { Text("Lúc nhập mã").foregroundStyle(.secondary); Text(Fmt.dateTime(s.reservedAt)) }
                    if let up = s.uploadedAt {
                        GridRow { Text("Lúc tải ảnh").foregroundStyle(.secondary); Text(Fmt.dateTime(up)) }
                    }
                    GridRow { Text("Trạng thái").foregroundStyle(.secondary); StatusChip(text: s.status.label, color: s.status.color) }
                    if s.status == .pending, let at = s.autoApproveAt {
                        GridRow { Text("Tự duyệt sau").foregroundStyle(.secondary); CountdownText(until: at).bold().foregroundStyle(.fmWarning) }
                    }
                    if let r = s.denyReason {
                        GridRow { Text("Lý do từ chối").foregroundStyle(.secondary); Text(r) }
                    }
                }
                if s.status == .pending {
                    HStack {
                        Button(role: .destructive) { showDeny = true } label: {
                            Label("Từ chối", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.fmSecondary).foregroundStyle(Color.fmDanger)
                        Button { confirmApprove = true } label: {
                            Label("Duyệt", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.fmPrimary)
                    }
                    .disabled(working)
                }
            } else {
            ContentUnavailableView("Mã đã được xử lý", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle("Mã")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Duyệt mã này?", isPresented: $confirmApprove, titleVisibility: .visible) {
            Button("Duyệt") { decide(approve: true) }
        } message: { Text("Mã sẽ vô hiệu, mọi người được báo và hint tiếp theo mở ngay.") }
        .alert("Từ chối mã", isPresented: $showDeny) {
            TextField("Lý do (người chơi sẽ thấy)", text: $reason)
            Button("Từ chối", role: .destructive) { decide(approve: false) }
            Button("Hủy", role: .cancel) {}
        } message: { Text("Mã sẽ được mở lại cho người khác.") }
        .errorAlert($error)
    }

    private func decide(approve: Bool) {
        guard let s = submission else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let r = reason.trimmingCharacters(in: .whitespaces)
                try await vm.review(s, approve: approve, reason: approve || r.isEmpty ? nil : r)
                dismiss()
            } catch {
                self.error = AppError.message(for: error)
                await vm.refresh()
            }
        }
    }
}

/// F-27 timeline, F-15 rewards payout, participants.
struct ActivityTab: View {
    @Environment(GameViewModel.self) private var vm
    @State private var section = 0
    @State private var error: String?

    var body: some View {
        List { ThemedRows {
            Picker("Mục", selection: $section) {
                Text("Dòng thời gian").tag(0)
                Text("Phần thưởng").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if section == 0 {
                EventTimelineList()
            } else {
                rewards
            }
        } }.fmScreen()
        .refreshable { await vm.refresh() }
        .errorAlert($error)
    }

    @ViewBuilder private var rewards: some View {
        if vm.rewards.isEmpty {
            Text("Chưa có phần thưởng nào.").foregroundStyle(.secondary)
        }
        ForEach(vm.rewards) { r in
            HStack {
                VStack(alignment: .leading) {
                    Text(vm.name(for: r.winnerId)).font(.headline)
                    Text(r.kind == .grand ? String(localized: "Giải tổng") : rewardHintLabel(r))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let item = r.item {
                    Label(item, systemImage: "gift").font(.subheadline.weight(.semibold)).lineLimit(2)
                } else {
                    Text(Fmt.money(r.amount, currency: r.currency)).font(.fmNumber)
                }
                Toggle("Đã trả", isOn: Binding(
                    get: { r.payoutStatus == .paid },
                    set: { paid in
                        Task {
                            do { try await API.setPayout(rewardId: r.id, paid: paid); await vm.refresh() }
                            catch { self.error = AppError.message(for: error) }
                        }
                    }))
                .labelsHidden()
                .accessibilityLabel(Text("Đã trả"))
            }
        }
    }

    private func rewardHintLabel(_ r: Reward) -> String {
        if let order = vm.hintOrder(for: r.hintId) { return String(localized: "Thưởng mốc Hint \(order)") }
        return String(localized: "Thưởng mốc")
    }
}

struct EventTimelineList: View {
    @Environment(GameViewModel.self) private var vm
    var body: some View {
        if vm.events.isEmpty { Text("Chưa có sự kiện nào.").foregroundStyle(.secondary) }
        ForEach(vm.events) { e in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: e.icon).foregroundStyle(.tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(describe(e)).font(.subheadline)
                    Text(Fmt.dateTime(e.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func describe(_ e: GameEvent) -> String {
        let order = e.value("hint_order")?.int ?? 0
        switch e.type {
        case "game_started": return String(localized: "Game bắt đầu")
        case "hint_activated": return String(localized: "Hint \(order) được mở")
        case "hint_item_revealed": return String(localized: "Khối gợi ý mới của Hint \(order) được mở")
        case "code_claimed": return String(localized: "Có người nhập đúng mã Hint \(order), đang chờ ảnh")
        case "proof_awaiting_review": return String(localized: "Một mã đang chờ duyệt")
        case "proof_review_reminder":
            let m = e.value("minutes")?.int ?? 0
            return String(localized: "Nhắc duyệt: mã đã chờ \(m) phút")
        case "proof_denied":
            let who = e.value("user_id")?.string.flatMap(UUID.init(uuidString:)).map(vm.name(for:)) ?? ""
            return String(localized: "Mã của \(who) bị từ chối")
        case "code_released":
            return e.value("reason")?.string == "denied"
                ? String(localized: "Mã Hint \(order) được mở lại (bị từ chối)")
                : String(localized: "Mã Hint \(order) được mở lại (hết hạn chụp ảnh)")
        case "hint_solved":
            let who = e.value("winner_name")?.string ?? ""
            let auto = e.value("auto_approved") == .bool(true)
            return auto ? String(localized: "\(who) đã tìm ra Hint \(order) (tự duyệt)")
                        : String(localized: "\(who) đã tìm ra Hint \(order)")
        case "hint_updated": return String(localized: "Quản trò đã cập nhật Hint \(order)")
        case "game_completed": return String(localized: "Game kết thúc")
        case "game_cancelled": return String(localized: "Game bị hủy")
        case "player_joined":
            let who = e.value("user_id")?.string.flatMap(UUID.init(uuidString:)).map(vm.name(for:)) ?? ""
            return String(localized: "\(who) đã tham gia")
        default: return e.type
        }
    }
}

extension GameEvent {
    /// Payload lookup tolerant to key-case conversion by the decoder.
    func value(_ snake: String) -> JSONValue? {
        if let v = payload[snake] { return v }
        let parts = snake.split(separator: "_")
        let camel = parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
        return payload[camel]
    }

    var icon: String {
        switch type {
        case "game_started": "flag"
        case "hint_activated", "hint_item_revealed": "lightbulb"
        case "code_claimed": "key"
        case "proof_awaiting_review", "proof_review_reminder": "hourglass"
        case "proof_denied": "xmark.circle"
        case "code_released": "lock.open"
        case "hint_solved": "checkmark.seal"
        case "game_completed": "trophy"
        case "game_cancelled": "xmark.octagon"
        case "player_joined": "person.badge.plus"
        default: "circle"
        }
    }
}
