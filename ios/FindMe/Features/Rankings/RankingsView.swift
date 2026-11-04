import SwiftUI

/// Bảng xếp hạng chung (tab "Xếp hạng"): Người chơi / Quản trò.
/// Server trả top 10 + dòng của mình nếu nằm ngoài top (get_player_rankings / get_host_rankings).
///
/// Bố cục: chọn bảng → thẻ "Hạng của bạn" → bục top 3 → danh sách hạng 4+ → "Cách tính hạng".
/// Mỗi chỉ số là một icon trong vòng tròn màu riêng + số to + nhãn đầy đủ (không viết tắt).
struct RankingsView: View {
    enum Board: Hashable { case players, hosts }

    @State private var board: Board = .players
    @State private var players: [PlayerRankingEntry] = []
    @State private var hosts: [HostRankingEntry] = []
    @State private var loaded: Set<Board> = []
    @State private var error: String?

    private var myId: UUID? { Supa.currentUserId }
    private static let limit = 10

    var body: some View {
        NavigationStack {
            // Cùng kiểu List (insetGrouped) với tab Game, nên lề trái/phải và khoảng cách giữa các
            // section giống hệt. Mỗi khối là một section, nền trong suốt, chiếm đủ bề rộng section.
            List {
                block { BoardPicker(board: $board) }
                switch board {
                case .players: boardContent(rows(players.map(playerItem)), empty: .players)
                case .hosts: boardContent(rows(hosts.map(hostItem)), empty: .hosts)
                }
            }
            .animation(.snappy, value: board)
            .fmScreen()
            .fmTabBarInset()
            .overlay { if !loaded.contains(board) { ProgressView().controlSize(.large) } }
            .refreshable { await load(board) }
            .navigationTitle("Xếp hạng")
            // Tiêu đề nhỏ trên thanh điều hướng: bỏ khoảng trống lớn của large title phía trên.
            .navigationBarTitleDisplayMode(.inline)
            .task(id: board) { if !loaded.contains(board) { await load(board) } }
            .errorAlert($error)
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func boardContent(_ data: (me: RankItem?, top: [RankItem]), empty: Board) -> some View {
        if loaded.contains(board) && data.top.isEmpty && data.me == nil {
            block { emptyState(empty) }
        } else {
            if let me = data.me { block { MyRankCard(item: me) } }
            let podium = Array(data.top.prefix(3))
            let rest = Array(data.top.dropFirst(3))
            if !podium.isEmpty { block { Podium(items: podium, myId: myId) } }
            if !rest.isEmpty {
                block {
                    RankTable(columns: board == .players ? Self.playerColumns : Self.hostColumns,
                              items: rest, myId: myId)
                }
            }
            block { HowRankingWorks(board: board) }
        }
    }

    /// Một khối = một section của List: nền trong suốt, không lề trong, không đường kẻ.
    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Section {
            content()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func emptyState(_ b: Board) -> some View {
        VStack(spacing: 12) {
            IconBubble(systemImage: b == .players ? "figure.walk" : "crown.fill",
                       tint: .fmAccent, size: 64)
            Text(b == .players ? "Chưa có ai trên bảng" : "Chưa có quản trò nào").font(.fmTitle3)
            Text(b == .players ? "Tham gia một game để có tên ở đây."
                               : "Tạo và chạy một game để có tên ở đây.")
                .font(.subheadline).foregroundStyle(Color.fmTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: Map rows → RankItem

    /// Tiêu đề cột của bảng hạng 4+ (cùng thứ tự với `RankItem.stats`).
    static let playerColumns = [
        RankColumn(systemImage: "trophy.fill", tint: .fmWarning, title: "Thắng"),
        RankColumn(systemImage: "lightbulb.fill", tint: .fmInfo, title: "Hint"),
        RankColumn(systemImage: "map.fill", tint: .fmSuccess, title: "Tham gia"),
    ]
    static let hostColumns = [
        RankColumn(systemImage: "star.fill", tint: .fmWarning, title: "Sao"),
        RankColumn(systemImage: "flag.fill", tint: .fmSuccess, title: "Tổ chức"),
        RankColumn(systemImage: "gift.fill", tint: .fmAccent, title: "Thưởng"),
    ]

    private func playerItem(_ e: PlayerRankingEntry) -> RankItem {
        RankItem(id: e.userId, rank: e.rank, name: e.displayName, avatarPath: e.avatarPath,
                 headline: RankStat(systemImage: "trophy.fill", tint: .fmWarning,
                                    value: "\(e.gamesWon)", label: "game thắng"),
                 stats: [
                    RankStat(systemImage: "trophy.fill", tint: .fmWarning,
                             value: "\(e.gamesWon)", label: "Thắng"),
                    RankStat(systemImage: "lightbulb.fill", tint: .fmInfo,
                             value: "\(e.hintsSolved)", label: "Hint đã giải"),
                    RankStat(systemImage: "map.fill", tint: .fmSuccess,
                             value: "\(e.gamesJoined)", label: "Đã tham gia"),
                 ])
    }

    private func hostItem(_ e: HostRankingEntry) -> RankItem {
        let stars = e.ratingAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–"
        let reward = e.rewardsVnd > 0
            ? RankStat(systemImage: "gift.fill", tint: .fmAccent,
                       value: Fmt.compactMoney(e.rewardsVnd), label: "Thưởng đã trao")
            : RankStat(systemImage: "gift.fill", tint: .fmAccent,
                       value: "\(e.rewardsGiven)", label: "Lượt thưởng")
        return RankItem(id: e.userId, rank: e.rank, name: e.displayName, avatarPath: e.avatarPath,
                        headline: RankStat(systemImage: "star.fill", tint: .fmWarning, value: stars,
                                           label: e.ratingCount > 0 ? "\(e.ratingCount) lượt chấm" : "chưa có lượt chấm"),
                        stats: [
                            RankStat(systemImage: "star.fill", tint: .fmWarning, value: stars,
                                     label: e.ratingCount > 0 ? "\(e.ratingCount) lượt chấm" : "Chưa chấm",
                                     detail: e.ratingCount > 0 ? "(\(e.ratingCount))" : nil),
                            RankStat(systemImage: "flag.fill", tint: .fmSuccess,
                                     value: "\(e.gamesCreated)", label: "Đã tổ chức"),
                            reward,
                        ])
    }

    // MARK: Data

    /// Dòng của mình được ghim lên thẻ "Hạng của bạn" (server luôn trả nó, kể cả khi ngoài top);
    /// danh sách top bỏ dòng đó nếu nó chỉ được đính kèm ở cuối.
    private func rows(_ items: [RankItem]) -> (me: RankItem?, top: [RankItem]) {
        guard let myId, let i = items.firstIndex(where: { $0.id == myId }) else { return (nil, items) }
        let outsideTop = items.count > Self.limit && i == items.count - 1
        return (items[i], outsideTop ? Array(items.dropLast()) : items)
    }

    private func load(_ b: Board) async {
        do {
            switch b {
            case .players: players = try await API.playerRankings(limit: Self.limit)
            case .hosts: hosts = try await API.hostRankings(limit: Self.limit)
            }
            loaded.insert(b)
        } catch {
            if !Task.isCancelled { self.error = AppError.message(for: error) }
        }
    }
}

// MARK: - Models

struct RankStat: Hashable {
    let systemImage: String
    let tint: Color
    let value: String
    let label: LocalizedStringKey
    /// Phụ chú nhỏ cạnh số trong bảng (vd. số lượt chấm).
    var detail: String? = nil

    static func == (a: RankStat, b: RankStat) -> Bool { a.systemImage == b.systemImage && a.value == b.value }
    func hash(into h: inout Hasher) { h.combine(systemImage); h.combine(value) }
}

struct RankItem: Identifiable, Hashable {
    let id: UUID
    let rank: Int
    let name: String
    let avatarPath: String?
    /// Chỉ số chính, hiện dưới tên trên bục.
    let headline: RankStat
    let stats: [RankStat]
}

// MARK: - Components

/// Chọn bảng: hai nút to có icon, thay cho segmented control chữ trơn.
private struct BoardPicker: View {
    @Binding var board: RankingsView.Board
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            option(.players, title: "Người chơi", icon: "figure.walk")
            option(.hosts, title: "Quản trò", icon: "crown.fill")
        }
        .padding(4)
        .background(Color.fmSunken, in: Capsule())
        .padding(.top, 4)
    }

    private func option(_ b: RankingsView.Board, title: LocalizedStringKey, icon: String) -> some View {
        let selected = board == b
        return Button { withAnimation(.snappy) { board = b } } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(selected ? Color.fmOnAccent : Color.fmTextSecondary)
                .background {
                    if selected {
                        Capsule().fill(Color.fmAccent).matchedGeometryEffect(id: "pill", in: ns)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Icon trong vòng tròn tô nhạt cùng màu.
private struct IconBubble: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

private enum Medal {
    static func color(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.85, green: 0.65, blue: 0.13)   // vàng
        case 2: Color(red: 0.62, green: 0.64, blue: 0.67)   // bạc
        default: Color(red: 0.72, green: 0.45, blue: 0.20)  // đồng
        }
    }
}

/// Thẻ "Hạng của bạn": hạng to + ba chỉ số.
private struct MyRankCard: View {
    let item: RankItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(path: item.avatarPath, name: item.name, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hạng của bạn").font(.caption.weight(.semibold)).foregroundStyle(Color.fmTextSecondary)
                    Text("Hạng #\(item.rank)").font(.fmTitle).foregroundStyle(Color.fmText)
                }
                Spacer()
                if item.rank <= 3 {
                    Image(systemName: "medal.fill").font(.title).foregroundStyle(Medal.color(item.rank))
                }
            }
            StatGrid(stats: item.stats)
        }
        .padding(12)
        .background(Color.fmAccentSoft, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmAccent.opacity(0.4)))
        .accessibilityElement(children: .combine)
    }
}

/// Ba ô chỉ số chia đều: icon tròn, số to, nhãn đầy đủ.
private struct StatGrid: View {
    let stats: [RankStat]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(stats, id: \.self) { s in
                VStack(spacing: 6) {
                    IconBubble(systemImage: s.systemImage, tint: s.tint)
                    Text(verbatim: s.value)
                        .font(.headline).monospacedDigit().foregroundStyle(Color.fmText)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(s.label)
                        .font(.caption2).foregroundStyle(Color.fmTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 4)
                .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radiusSmall, style: .continuous))
            }
        }
    }
}

/// Bục top 3: hạng 2 – 1 – 3, người nhất ở giữa và cao nhất.
private struct Podium: View {
    let items: [RankItem]
    let myId: UUID?

    var body: some View {
        let order = [1, 0, 2].filter { $0 < items.count }.map { items[$0] }
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(order) { item in
                PodiumSpot(item: item, isMe: item.id == myId)
            }
        }
    }
}

private struct PodiumSpot: View {
    let item: RankItem
    let isMe: Bool

    private var isFirst: Bool { item.rank == 1 }

    var body: some View {
        VStack(spacing: 8) {
            if isFirst {
                Image(systemName: "crown.fill").font(.title2).foregroundStyle(Medal.color(1))
                    .accessibilityHidden(true)
            }
            ZStack(alignment: .bottom) {
                AvatarView(path: item.avatarPath, name: item.name, size: isFirst ? 76 : 60)
                    .overlay(Circle().strokeBorder(Medal.color(item.rank), lineWidth: 3))
                Text("\(item.rank)")
                    .font(.caption.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Medal.color(item.rank), in: Circle())
                    .overlay(Circle().strokeBorder(Color.fmCanvas, lineWidth: 2))
                    .offset(y: 10)
            }
            .padding(.bottom, 8)
            Text(item.name + (isMe ? String(localized: " (bạn)") : ""))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.fmText)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
            HStack(spacing: 4) {
                Image(systemName: item.headline.systemImage).foregroundStyle(item.headline.tint)
                Text(verbatim: item.headline.value).font(.headline).monospacedDigit()
            }
            Text(item.headline.label)
                .font(.caption2).foregroundStyle(Color.fmTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 10).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(isMe ? Color.fmAccentSoft : Color.fmSurface,
                    in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous)
            .strokeBorder(isFirst ? Medal.color(1).opacity(0.6) : Color.fmBorder, lineWidth: isFirst ? 1.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Hạng \(item.rank), \(item.name)"))
    }
}

struct RankColumn: Hashable {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey

    static func == (a: RankColumn, b: RankColumn) -> Bool { a.systemImage == b.systemImage }
    func hash(into h: inout Hasher) { h.combine(systemImage) }
}

/// Bảng hạng 4+: hàng tiêu đề (icon màu + tên cột), mỗi người một hàng, cột số căn phải đều nhau,
/// hàng xen kẽ màu, hàng của mình tô màu nhấn.
private struct RankTable: View {
    let columns: [RankColumn]
    let items: [RankItem]
    let myId: UUID?

    @ScaledMetric(relativeTo: .subheadline) private var statWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .subheadline) private var rankWidth: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Color.fmBorder.opacity(0.6)) }
                row(item, striped: index.isMultiple(of: 2) == false)
            }
        }
        .background(Color.fmSurface)
        .clipShape(RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(verbatim: "#").frame(width: rankWidth)
            Text("Tên").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { c in
                VStack(spacing: 2) {
                    Image(systemName: c.systemImage).foregroundStyle(c.tint)
                    // Cỡ chữ cố định cho mọi cột (không tự co từng ô), xuống dòng nếu dài.
                    Text(c.title).lineLimit(2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: statWidth)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.fmTextSecondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.fmSunken)
        .accessibilityHidden(true)
    }

    private func row(_ item: RankItem, striped: Bool) -> some View {
        let isMe = item.id == myId
        return HStack(spacing: 4) {
            Text("\(item.rank)")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Color.fmTextSecondary)
                .frame(width: rankWidth)
            HStack(spacing: 6) {
                AvatarView(path: item.avatarPath, name: item.name, size: 26)
                // Tên dài xuống dòng (tối đa 2) thay vì bị cắt "…".
                Text(item.name + (isMe ? String(localized: " (bạn)") : ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.fmText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(item.stats, id: \.self) { s in
                // Mọi ô cùng một cỡ chữ; phụ chú (số lượt chấm) xuống dòng dưới thay vì chen cạnh số
                // làm ô đó bị co nhỏ hơn các ô khác.
                VStack(spacing: 0) {
                    Text(verbatim: s.value).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Color.fmText)
                    if let d = s.detail {
                        Text(verbatim: d).font(.caption2).monospacedDigit().foregroundStyle(Color.fmTextSecondary)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.9)
                .frame(width: statWidth)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(isMe ? Color.fmAccentSoft : (striped ? Color.fmCanvas.opacity(0.5) : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(item)))
    }

    private func accessibilityText(_ item: RankItem) -> String {
        let stats = zip(columns, item.stats).map { "\($0.1.value)" }.joined(separator: ", ")
        return String(localized: "Hạng \(item.rank), \(item.name)") + ", " + stats
    }
}

/// "Cách tính hạng": gập/mở, mỗi tiêu chí một dòng có icon.
private struct HowRankingWorks: View {
    let board: RankingsView.Board
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if board == .players {
                    rule("trophy.fill", .fmWarning, "Số game thắng (giải tổng)")
                    rule("lightbulb.fill", .fmInfo, "Bằng nhau thì xét số hint đã giải")
                    rule("map.fill", .fmSuccess, "Rồi đến số game đã tham gia")
                } else {
                    rule("star.fill", .fmWarning, "Độ uy tín: số sao người chơi chấm sau mỗi game. Ít lượt chấm thì được tính gần mức 3★")
                    rule("flag.fill", .fmSuccess, "Bằng nhau thì xét số game đã tổ chức")
                    rule("gift.fill", .fmAccent, "Rồi đến tổng thưởng đã trao (chỉ cộng các game dùng VND)")
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Cách tính hạng", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.fmText)
        }
        .tint(Color.fmTextSecondary)
        .padding(FM.pad)
        .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder))
    }

    private func rule(_ icon: String, _ tint: Color, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconBubble(systemImage: icon, tint: tint, size: 26)
            Text(text).font(.footnote).foregroundStyle(Color.fmTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
