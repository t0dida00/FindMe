import MapKit
import SwiftUI

/// F-17..F-20: current hint, revealed blocks, countdown to next block, code entry, proof status.
struct HintTab: View {
    @Environment(GameViewModel.self) private var vm
    @State private var proofTarget: ProofTarget?

    var body: some View {
        FMScrollScreen(alignment: .leading) {
            if let game = vm.game {
                switch game.status {
                case .draft, .scheduled:
                    LobbyWaitingView(game: game)
                case .live:
                    liveContent
                case .completed, .cancelled:
                    EmptyView()
                }
            }
            if let err = vm.loadError {
                Label(err, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.fmWarning)
            }
        }
        .refreshable { await vm.refresh() }
        .fullScreenCover(item: $proofTarget) { target in
            ProofCaptureView(target: target) { Task { await vm.refresh() } }
        }
    }

    @ViewBuilder private var liveContent: some View {
        if let hint = vm.currentHint {
            HintHeader(hint: hint, currency: vm.game?.currency ?? "VND")
            ForEach(hint.items) { item in HintItemView(item: item) }
            if let next = vm.nextRevealAt {
                HStack {
                    Image(systemName: "hourglass")
                    Text("Khối gợi ý tiếp theo mở sau")
                    CountdownText(until: next).font(.headline)
                }
                .fmCallout(.fmInfo)
                .accessibilityElement(children: .combine)
            }
            ProofSection(hint: hint, onReserved: { proofTarget = $0 })
        } else {
            ContentUnavailableView {
                Label("Hint đang được chuẩn bị", systemImage: "hourglass")
            } description: {
                if let next = vm.nextRevealAt {
                    HStack { Text("Gợi ý đầu tiên mở sau"); CountdownText(until: next) }
                } else {
                    Text("Hint tiếp theo sẽ xuất hiện ngay khi có khối gợi ý được mở.")
                }
            }
        }

        if !vm.solvedHints.isEmpty {
            TreasureDivider().padding(.vertical, 4)
            Text("Hint đã giải").font(.fmTitle3)
            SolvedTimeline(hints: vm.solvedHints, answers: vm.revealedAnswers, startedAt: vm.game?.startedAt)
        }
    }
}

/// Dòng thời gian các hint đã giải: trên cùng là mới nhất, gốc dưới cùng là lúc game bắt đầu.
/// Mỗi mốc là một nút trên trục dọc; chạm để mở lại các khối gợi ý của hint đó.
private struct SolvedTimeline: View {
    /// Đã sắp mới nhất trước (GameViewModel.solvedHints).
    let hints: [PlayerHint]
    let answers: [RevealedAnswer]
    let startedAt: Date?

    private static let rail: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hints.enumerated()), id: \.element.id) { index, hint in
                node(icon: "checkmark", tint: index == 0 ? .fmSuccess : .fmAccent, last: false) {
                    hintRow(hint)
                }
            }
            node(icon: "flag.fill", tint: .fmAccent, last: true) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game bắt đầu").font(.fmHeadline).foregroundStyle(Color.fmText)
                    if let startedAt {
                        Text(verbatim: Fmt.dateTime(startedAt))
                            .font(.caption).monospacedDigit().foregroundStyle(Color.fmTextSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func hintRow(_ hint: PlayerHint) -> some View {
        let answer = answers.first { $0.hintOrder == hint.order }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: FM.s) {
                ForEach(hint.items) { HintItemView(item: $0) }
            }
            .padding(.top, FM.s)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let answer {
                    Text(verbatim: Fmt.shortTime(answer.solvedAt))
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Color.fmTextSecondary)
                }
                Text("Hint \(hint.order)\(hint.title.map { ": \($0)" } ?? "")")
                    .font(.fmHeadline).foregroundStyle(Color.fmText)
                    .multilineTextAlignment(.leading)
                if let answer {
                    Label { Emphasis.keyword("Người tìm ra:", answer.winnerName) } icon: { Image(systemName: "trophy") }
                        .font(.caption).foregroundStyle(Color.fmTextSecondary)
                }
            }
        }
        .tint(Color.fmTextSecondary)
    }

    /// Một mốc: nút tròn trên trục + nội dung bên phải; đoạn trục nối xuống mốc cũ hơn bên dưới.
    private func node<Content: View>(icon: String, tint: Color, last: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.rail + FM.m)
            .padding(.bottom, last ? 0 : FM.xl)
            .background(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.fmOnAccent)
                        .frame(width: Self.rail, height: Self.rail)
                        .background(tint, in: Circle())
                        .overlay(Circle().strokeBorder(Color.fmCanvas, lineWidth: 2))
                    if !last {
                        Rectangle().fill(Color.fmBorder).frame(width: 2).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: Self.rail)
                .accessibilityHidden(true)
            }
    }
}

struct HintHeader: View {
    let hint: PlayerHint
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HINT \(hint.order)")
                .font(.caption.weight(.heavy)).tracking(1.5).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.fmAccentSoft, in: Capsule())
                .foregroundStyle(Color.fmAccent)
            if let title = hint.title {
                Text(title).font(.system(.title).weight(.bold)).foregroundStyle(Color.fmText)
                    .fmTitleLines()
            }
            if let description = hint.description {
                Text(description).font(.body).foregroundStyle(Color.fmTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prize = Fmt.prize(hint.prize, item: hint.prizeItem, currency: currency) {
                PrizeBanner(amount: prize).padding(.top, FM.s)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Khối nổi bật cho thưởng mốc: ô icon quà · nhãn "Thưởng mốc" · số tiền hoặc tên hiện vật, màu kho báu.
struct PrizeBanner: View {
    let amount: String
    var body: some View {
        HStack(spacing: FM.m) {
            Image(systemName: "gift.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.fmOnTreasure)
                .frame(width: 44, height: 44)
                .background(Color.fmTreasure.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Thưởng mốc").font(.fmCaps).textCase(.uppercase).tracking(1)
                    .foregroundStyle(Color.fmTextSecondary)
                Text(verbatim: amount).font(.title2.weight(.bold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.fmTreasure)
            }
            Spacer(minLength: 0)
        }
        .padding(FM.m)
        .background(Color.fmTreasure.opacity(0.10), in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous)
            .strokeBorder(Color.fmTreasure.opacity(0.35), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

struct HintItemView: View {
    let item: HintItemRow
    var body: some View {
        HintBlockView(type: item.type, text: item.textContent, imagePath: item.imagePath,
                      lat: item.mapCenterLat, lng: item.mapCenterLng, radius: item.mapRadiusM)
    }
}

/// Renders one text / image / map block (used by players and the host preview).
struct HintBlockView: View {
    let type: HintItemType
    let text: String?
    let imagePath: String?
    let lat: Double?
    let lng: Double?
    let radius: Int?

    var body: some View {
        switch type {
        case .text:
            Text(text ?? "")
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(Color.fmText)
                .fmCard()
        case .image:
            if let imagePath {
                SignedImage(bucket: "hint-media", path: imagePath)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Ảnh gợi ý"))
            }
        case .map:
            if let lat, let lng, let radius {
                HintAreaMap(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), radius: Double(radius))
            } else {
                Text("Vùng bản đồ sẽ được tạo khi lưu.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct HintAreaMap: View {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: radius * 2.6,
                                                        longitudinalMeters: radius * 2.6))) {
            MapCircle(center: center, radius: radius)
                .foregroundStyle(.fmAccent.opacity(0.25))
                .stroke(.fmAccent, lineWidth: 2)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder))
        .accessibilityLabel(Text("Vùng tìm kiếm bán kính \(Int(radius)) mét"))
    }
}

/// Code entry + own proof status for the current hint.
struct ProofSection: View {
    @Environment(GameViewModel.self) private var vm
    let hint: PlayerHint
    let onReserved: (ProofTarget) -> Void
    @State private var code = ""
    @State private var message: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nộp mã", systemImage: "seal").font(.fmTitle3).foregroundStyle(Color.fmText)
            if let sub = vm.currentSubmission {
                SubmissionStatusCard(submission: sub, onResume: vm.resumableTarget.map { t in { onReserved(t) } })
            }
            if canEnterCode {
                codeEntry
            }
        }
        .fmCard()
    }

    private var mineOpen: Bool {
        guard let s = vm.currentSubmission else { return false }
        return s.status == .reserved || s.status == .pending
    }

    private var canEnterCode: Bool { !mineOpen && !hint.solved }

    @ViewBuilder private var codeEntry: some View {
        let lockedUntil = vm.codeState?.lockedUntil.flatMap { $0 > Date() ? $0 : nil }
        if let lockedUntil {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bạn đã nhập sai quá nhiều lần", systemImage: "lock.fill").foregroundStyle(.fmDanger)
                HStack { Text("Có thể nhập lại sau"); CountdownText(until: lockedUntil).font(.title3.weight(.bold)) }
            }
            .accessibilityElement(children: .combine)
            .task(id: lockedUntil) {
                try? await Task.sleep(for: .seconds(max(0, lockedUntil.timeIntervalSinceNow) + 1))
                await vm.refresh()
            }
        } else if vm.codeStatus == .inReview {
            Label("Có người đang xác minh mã này", systemImage: "hourglass")
                .foregroundStyle(.fmAccent)
            Text("Nếu mã của họ bị từ chối hoặc hết hạn, mã sẽ được mở lại.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Tìm tờ giấy mã tại địa điểm, nhập mã in trên đó, rồi chụp ảnh tờ giấy trong \(vm.game?.uploadWindowSeconds ?? 60) giây.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                TextField("Nhập mã", text: $code)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .tracking(2)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .padding(FM.m)
                    .frame(minHeight: 50)
                    .background(Color.fmSunken, in: RoundedRectangle(cornerRadius: FM.radiusSmall, style: .continuous))
                Button { submit() } label: {
                    if working { ProgressView().tint(.fmOnTreasure) } else { Text("Gửi mã") }
                }
                .buttonStyle(.fmPrimaryCompact)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            if let left = vm.codeState?.attemptsBeforeLock, let max = vm.game?.codeFailsBeforeLock, left < max {
                Text("Còn \(left) lần thử trước khi bị khóa").font(.footnote).foregroundStyle(.fmWarning)
            }
        }
        if let message {
            Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(.fmDanger)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func submit() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !working else { return }
        working = true
        message = nil
        Task {
            defer { working = false }
            switch await vm.redeem(code: trimmed) {
            case .reserved(let target):
                code = ""
                onReserved(target)
            case .message(let m):
                message = m
                UIAccessibility.post(notification: .announcement, argument: m)
            }
        }
    }
}

/// F-19: reserved / pending (countdown to auto approve) / approved / denied (reason) / expired.
struct SubmissionStatusCard: View {
    let submission: Submission
    var onResume: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mã của bạn").font(.fmHeadline)
                Spacer()
                StatusChip(text: submission.status.label, color: submission.status.color)
            }
            switch submission.status {
            case .reserved:
                HStack { Text("Thời gian chụp ảnh còn"); CountdownText(until: submission.uploadDeadline).bold() }
                if let onResume {
                    Button("Mở camera", systemImage: "camera") { onResume() }.buttonStyle(.fmPrimary)
                }
            case .pending:
                if let at = submission.autoApproveAt {
                    HStack { Text("Quản trò đang duyệt · tự duyệt sau"); CountdownText(until: at).bold() }
                } else {
                    Text("Quản trò đang duyệt ảnh của bạn.")
                }
            case .approved:
                Text("Chúc mừng! Bạn đã tìm ra hint này.")
            case .denied:
                Text("Lý do: \(submission.denyReason ?? String(localized: "không có"))")
                Text("Bạn có thể nhập lại mã nếu tìm được tờ giấy đúng.").font(.footnote).foregroundStyle(.secondary)
            case .expired:
                Text("Quá thời hạn chụp ảnh, mã đã được mở lại.")
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct LobbyWaitingView: View {
    @Environment(GameViewModel.self) private var vm
    let game: Game
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.2.crossed").font(.system(size: 48))
                .foregroundStyle(Color.fmAccent)
                .frame(width: 112, height: 112)
                .background(Color.fmAccentSoft, in: Circle())
            Text("Game chưa bắt đầu").font(.fmTitle)
            TreasureDivider().frame(width: 140)
            if game.status == .scheduled, let at = game.startsAt {
                Text("Bắt đầu lúc \(Fmt.dateTime(at))")
                HStack { Text("Còn"); CountdownText(until: at).font(.title.weight(.bold)) }
            } else {
                Text("Chờ quản trò bắt đầu…").foregroundStyle(.secondary)
            }
            Text("\(vm.participants.filter { $0.role == .player }.count) người chơi đã tham gia")
                .foregroundStyle(.secondary)
            if let d = game.description, !d.isEmpty { Text(d).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// Player "Thông tin" tab: game info, own proof history, leave game (F-22).
struct PlayerInfoTab: View {
    @Environment(GameViewModel.self) private var vm
    let onLeft: () -> Void
    @State private var confirmLeave = false
    @State private var error: String?

    var body: some View {
        List { ThemedRows {
            if let game = vm.game {
                Section {
                    LabeledContent("Trạng thái") { StatusChip(text: game.status.label, color: game.status.color) }
                    LabeledContent("Mã tham gia", value: game.joinCode).monospacedDigit()
                    LabeledContent("Người tham gia") {
                        let players = vm.participants.filter { $0.role == .player }.count
                        // Có giới hạn thì hiện "12/30", không thì chỉ số người.
                        Text(verbatim: game.maxPlayers.map { "\(players)/\($0)" } ?? "\(players)")
                            .monospacedDigit()
                    }
                    LabeledContent("Giải thưởng tổng",
                                   value: Fmt.prize(game.grandPrize, item: game.grandPrizeItem, currency: game.currency) ?? "—")
                    if let d = game.description, !d.isEmpty { Text(d) }
                }
                Section {
                    ShareLink(item: AppConfig.joinLink(code: game.joinCode),
                              message: Text("Tham gia game \"\(game.title)\" trên Find Me! Mã: \(game.joinCode)")) {
                        Label("Mời bạn bè", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section {
                NavigationLink {
                    List { EventTimelineList() }
                        .navigationTitle("Dòng thời gian")
                        .refreshable { await vm.refresh() }
                        .fmTabBarInset()
                } label: { Label("Dòng thời gian sự kiện", systemImage: "clock.arrow.circlepath") }
            }
            if !vm.mySubmissions.isEmpty {
                Section("Lịch sử mã của bạn") {
                    ForEach(vm.mySubmissions) { s in
                        HStack {
                            Text(Fmt.dateTime(s.reservedAt)).font(.subheadline)
                            Spacer()
                            StatusChip(text: s.status.label, color: s.status.color)
                        }
                    }
                }
            }
            Section {
                Button("Rời game", role: .destructive) { confirmLeave = true }
            }
        } }.fmScreen()
        .refreshable { await vm.refresh() }
        .confirmationDialog("Rời game này?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời game", role: .destructive) {
                Task {
                    do { try await vm.leave(); onLeft() } catch { self.error = AppError.message(for: error) }
                }
            }
        } message: {
            Text("Bạn có thể tham gia lại bằng mã nếu game chưa kết thúc.")
        }
        .errorAlert($error)
    }
}
