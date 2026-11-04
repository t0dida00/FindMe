import SwiftUI

/// Tab "Game": header (logo · avatar), game của tôi hoặc 2 ô Tham gia/Tạo,
/// lưới các game công khai, rồi lịch sử gần đây.
/// Luật "1 người, 1 game" (20261103000500_one_active_hunt.sql): khi đang ở trong một game
/// chưa kết thúc thì không tạo hay tham gia game khác. Server chặn; app chỉ ẩn nút và giải thích.
struct HomeView: View {
    /// Mở game (MainTabView trình bày GameScreen toàn màn hình).
    let open: (UUID) -> Void
    /// Mở sheet nhập mã tham gia.
    let join: () -> Void
    /// Chuyển sang tab Hồ sơ (nút avatar trên header).
    let showProfile: () -> Void
    /// Tăng lên mỗi khi GameScreen đóng, để tải lại danh sách.
    let reloadTick: Int
    /// Báo cho MainTabView biết đang có game chưa kết thúc (để hiện huy hiệu trên tab).
    var activeChanged: (Bool) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @State private var games: [MyGameEntry] = []
    @State private var publicGames: [GlobeGame] = []
    @State private var history: [HistoryEntry] = []
    @State private var profile: Profile?
    @State private var loaded = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var selected: GlobeGame?
    /// Tab ở mục game công khai và số thẻ đang hiện (mỗi lần "Xem thêm" cộng thêm `pageSize`).
    @State private var publicTab: PublicTab = .live
    @State private var shownCount = HomeView.pageSize
    @State private var pickedPublicTab = false
    /// Số liệu của game đang tham gia (gắn với id để không hiện số của game cũ).
    @State private var summary: (gameId: UUID, value: GameSummary)?

    private static let recentCount = 3
    private static let pageSize = 10

    enum PublicTab: Hashable { case live, upcoming }

    /// Đang diễn ra: mới bắt đầu trước. Sắp diễn ra: giờ bắt đầu gần nhất trước.
    private var liveGames: [GlobeGame] {
        others.filter { $0.status == .live }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }
    private var upcomingGames: [GlobeGame] {
        others.filter { $0.status == .scheduled }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }
    private var active: MyGameEntry? { games.activeHunt }
    private var others: [GlobeGame] { publicGames.filter { $0.myRole == nil } }

    var body: some View {
        NavigationStack {
            FMScrollScreen {
                header
                mySection
                publicSections
                historySection
            }
            .fmTabBarInset()
            .overlay { if !loaded { ProgressView().controlSize(.large) } }
            .refreshable { await load() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Find Me!")
            .task { await load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
            .onChange(of: reloadTick) { _, _ in Task { await load() } }
            .sheet(isPresented: $showCreate) {
                CreateGameView { game in showCreate = false; open(game.id) }
            }
            .sheet(item: $selected) { game in
                GlobeGameCard(game: game, blockedBy: active?.game.title,
                              open: { selected = nil; open(game.id) },
                              join: { selected = nil; join() })
                    .presentationDetents([.height(360), .medium])
                    .presentationBackground(Color.fmCanvas)
            }
            .errorAlert($error)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: FM.m) {
            FMLogoMark(size: 44)
            FMWordmark(size: 26)
            Spacer(minLength: FM.s)
            Button(action: showProfile) {
                AvatarView(path: profile?.avatarPath, name: profile?.displayName ?? "", size: 36)
                    .frame(width: 48, height: 48)
                    .background(Color.fmAccentSoft, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1.5))
            }
            .buttonStyle(FMTilePressStyle())
            .accessibilityLabel(Text("Hồ sơ"))
        }
        .padding(.top, FM.s)
        .padding(.bottom, FM.s)
    }

    // MARK: Game của tôi

    @ViewBuilder private var mySection: some View {
        if let active {
            FMSectionLabel(text: "Game của tôi")
            MyGameCard(entry: active, summary: summary?.gameId == active.game.id ? summary?.value : nil) {
                open(active.game.id)
            }
            note("Khi game này kết thúc (hoặc bạn rời đi) bạn mới tham gia hay tạo được game khác.")
        } else if loaded {
            FMTileGrid() {
                FMTile(systemImage: "person.badge.plus", tint: .fmTreasure,
                       title: Text("Tham gia"), subtitle: Text("Nhập mã 6 ký tự từ quản trò"), action: join)
                FMTile(systemImage: "plus", tint: .fmAccent,
                       title: Text("Tạo game"), subtitle: Text("Soạn hint và mời bạn bè")) { showCreate = true }
            }
            note("Mỗi người chỉ ở trong 1 game tại một thời điểm.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote).foregroundStyle(Color.fmTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FM.s)
    }

    // MARK: Các game công khai

    @ViewBuilder private var publicSections: some View {
        let live = liveGames
        let upcoming = upcomingGames
        if loaded && live.isEmpty && upcoming.isEmpty {
            FMSectionLabel(text: "Các game")
            FMGroup {
                FMRow(systemImage: "globe.asia.australia", tint: .fmInfo,
                      title: Text("Chưa có game công khai nào"),
                      subtitle: Text("Quản trò có thể chọn \"Công khai\" khi tạo game để game xuất hiện ở đây."))
            }
        } else if !live.isEmpty || !upcoming.isEmpty {
            let list = publicTab == .live ? live : upcoming
            FMSectionLabel(text: "Các game")
            Picker("Các game", selection: $publicTab) {
                Text("Đang diễn ra").tag(PublicTab.live)
                Text("Sắp diễn ra").tag(PublicTab.upcoming)
            }
            .pickerStyle(.segmented)
            .onChange(of: publicTab) { pickedPublicTab = true; shownCount = Self.pageSize }
            if list.isEmpty {
                FMGroup {
                    FMRow(systemImage: publicTab == .live ? "flag.checkered" : "calendar", tint: .fmInfo,
                          title: publicTab == .live ? Text("Chưa có game nào đang diễn ra")
                                                    : Text("Chưa có game nào sắp diễn ra"))
                }
            } else {
                tileGrid(Array(list.prefix(shownCount)))
                if list.count > shownCount {
                    Button {
                        withAnimation { shownCount += Self.pageSize }
                    } label: {
                        Label("Xem thêm", systemImage: "chevron.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.fmSecondary)
                }
            }
        }
    }

    /// Lần đầu tải: chưa có game đang diễn ra thì mở sẵn tab "Sắp diễn ra".
    private func pickDefaultPublicTab() {
        guard !pickedPublicTab else { return }
        publicTab = liveGames.isEmpty && !upcomingGames.isEmpty ? .upcoming : .live
    }

    /// Mỗi game một hàng: thẻ ngang rộng hết màn hình.
    private func tileGrid(_ list: [GlobeGame]) -> some View {
        VStack(spacing: FM.m) {
            ForEach(list) { game in
                GameRowCard(game: game) { selected = game }
                    .accessibilityHint(Text("Xem chi tiết game"))
            }
        }
    }

    // MARK: Lịch sử

    @ViewBuilder private var historySection: some View {
        let past = history.filter { $0.status.isFinished }
        if !past.isEmpty {
            FMSectionLabel(text: "Lịch sử của tôi")
            FMGroup {
                ForEach(Array(past.prefix(Self.recentCount).enumerated()), id: \.element.id) { i, entry in
                    if i > 0 { FMGroupDivider() }
                    HistoryRow(entry: entry) { open(entry.gameId) }
                }
            }
            if !past.isEmpty {
                FMGroup {
                    NavigationLink {
                        HistoryListView(entries: past, open: open)
                    } label: {
                        FMRow(systemImage: "clock.arrow.circlepath", title: Text("Tất cả \(past.count) game"),
                              chevron: false) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold)).foregroundStyle(Color.fmTextSecondary)
                        }
                    }
                    .buttonStyle(FMRowPressStyle())
                }
            }
        }
    }

    private func load() async {
        async let mine = API.myGames()
        async let pub = API.globeGames()
        async let hist = API.myHistory()
        async let me = API.myProfile()
        do {
            games = try await mine
            activeChanged(games.activeHunt != nil)
        } catch { self.error = AppError.message(for: error) }
        do { publicGames = try await pub } catch { if self.error == nil { self.error = AppError.message(for: error) } }
        pickDefaultPublicTab()
        if let id = games.activeHunt?.game.id, let value = try? await API.gameSummary(gameId: id) {
            summary = (id, value)
        }
        // Không nuốt lỗi: lỗi server (vd. thiếu migration) phải hiện ra, không thì lịch sử cứ cũ mà không ai biết.
        do { history = try await hist } catch { if self.error == nil { self.error = AppError.message(for: error) } }
        profile = (try? await me) ?? profile
        loaded = true
    }
}

/// Thẻ ngang cho một game công khai: icon trạng thái · tên, quản trò, giờ bắt đầu / khu vực ·
/// giải thưởng và số người chơi bên phải.
struct GameRowCard: View {
    let game: GlobeGame
    let action: () -> Void

    private var live: Bool { game.status == .live }
    private var tint: Color { live ? .fmTreasure : .fmInfo }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: FM.m) {
                HStack(alignment: .top, spacing: FM.m) {
                    FMIconTile(systemImage: live ? "flag.checkered" : "calendar", tint: tint, size: 52, filled: true)
                    VStack(alignment: .leading, spacing: FM.xs) {
                        Text(game.title).font(.headline).foregroundStyle(Color.fmText)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: FM.s - 2) {
                            AvatarView(path: game.hostAvatarPath, name: game.hostName, size: 22)
                            Text(verbatim: game.hostName).font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.fmTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    StatusChip(text: game.status.label, color: game.status.color)
                }
                // Mỗi thông tin một dòng, không cắt chữ ("…").
                VStack(alignment: .leading, spacing: FM.xs + 2) {
                    if let when = live ? game.startedAt : game.startsAt {
                        info("clock", Text(verbatim: Fmt.dateTime(when)).monospacedDigit())
                    }
                    info("person.2.fill", Text("\(game.playerCount) người chơi"))
                    if let area = game.areaName, !area.isEmpty {
                        info("mappin.and.ellipse", Text(verbatim: area))
                    }
                    if game.grandPrize > 0 {
                        info("gift.fill", Text(verbatim: Fmt.money(game.grandPrize, currency: game.currency))
                                .bold().foregroundStyle(Color.fmTreasure), tint: .fmTreasure)
                    }
                }
            }
            .padding(FM.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                    .fill(Color.fmSurface)
                    .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)))
            }
            .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
        }
        .buttonStyle(FMTilePressStyle())
    }

    private func info(_ systemImage: String, _ text: Text, tint: Color = .fmTextSecondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FM.s) {
            Image(systemName: systemImage).foregroundStyle(tint).frame(width: 18)
            text.foregroundStyle(Color.fmText).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

/// Card lớn "Game của tôi": trạng thái, tên, quản trò, mã tham gia, rồi lưới thông tin
/// (giải thưởng, người chơi, giờ bắt đầu, địa điểm, hint x/y) và nút vào game.
struct MyGameCard: View {
    let entry: MyGameEntry
    let summary: GameSummary?
    let open: () -> Void

    private var game: Game { entry.game }

    var body: some View {
        VStack(alignment: .leading, spacing: FM.pad) {
            header
            codeBox
            FMTileGrid(spacing: FM.s) {
                InfoCell(systemImage: "gift.fill", tint: .fmTreasure, label: "Giải thưởng",
                         value: Text(verbatim: grandPrizeText ?? "—")
                            .foregroundStyle(grandPrizeText != nil ? Color.fmTreasure : Color.fmTextSecondary))
                InfoCell(systemImage: "person.2.fill", label: "Người chơi", value: playersText)
                InfoCell(systemImage: "calendar", label: game.startedAt == nil ? "Ngày bắt đầu" : "Đã bắt đầu",
                         value: Text(verbatim: (game.startedAt ?? game.startsAt).map(Fmt.dateTime) ?? "—"))
                InfoCell(systemImage: "flag.fill", label: "Hint", value: hintsText)
            }
            InfoCell(systemImage: "mappin.and.ellipse", label: "Địa điểm",
                     value: Text(verbatim: game.areaName ?? "—"), lineLimit: 2)
            Button(action: open) {
                Label(game.status == .live ? "Vào game" : "Mở game", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.fmPrimary)
        }
        .padding(FM.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                .fill(Color.fmSurface)
                .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                    .fill(LinearGradient(colors: [game.status.color.opacity(0.14), .clear], startPoint: .top, endPoint: .center)))
        }
        .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
        .fmShimmer(tint: game.status.color)
        .contentShape(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityHint(Text("Mở game"))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: FM.m) {
            FMIconTile(systemImage: entry.role.isStaff ? "crown.fill" : "figure.walk",
                       tint: game.status.color, size: 52, filled: true)
            VStack(alignment: .leading, spacing: FM.xs) {
                HStack(spacing: FM.s) {
                    StatusChip(text: game.status.label, color: game.status.color)
                    Text(entry.role.label).font(.caption.weight(.semibold)).foregroundStyle(Color.fmTextSecondary)
                }
                Text(game.title).font(.fmTitle).foregroundStyle(Color.fmText).lineLimit(2)
                if let host = summary?.hostName {
                    HStack(spacing: FM.s - 2) {
                        AvatarView(path: summary?.hostAvatarPath, name: host, size: 20)
                        Text(verbatim: host).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fmTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var codeBox: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mã tham gia").font(.fmCaps).textCase(.uppercase).foregroundStyle(Color.fmTextSecondary)
                Text(verbatim: game.joinCode).font(.fmCode).tracking(4).foregroundStyle(Color.fmText)
            }
            Spacer()
            FMCopyButton(value: game.joinCode, toast: "Đã copy ID", accessibilityLabel: "Sao chép mã")
                .buttonStyle(.fmPill)
        }
        .padding(.horizontal, FM.m).padding(.vertical, FM.s)
        .background(Color.fmSunken, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
    }

    private var grandPrizeText: String? {
        Fmt.prize(game.grandPrize, item: game.grandPrizeItem, currency: game.currency)
    }

    private var playersText: Text {
        guard let count = summary?.playerCount else { return Text(verbatim: "—") }
        if let max = game.maxPlayers { return Text(verbatim: "\(count.formatted())/\(max.formatted())") }
        return Text(verbatim: count.formatted())
    }

    private var hintsText: Text {
        guard let s = summary else { return Text(verbatim: "—") }
        return Text(verbatim: "\(s.solvedCount.formatted())/\(s.hintCount.formatted())")
    }
}

/// Ô thông tin nhỏ trong MyGameCard: icon · nhãn, giá trị đậm bên dưới.
private struct InfoCell: View {
    let systemImage: String
    var tint: Color = .fmAccent
    let label: LocalizedStringKey
    let value: Text
    var lineLimit = 1

    var body: some View {
        HStack(alignment: .top, spacing: FM.s) {
            FMIconTile(systemImage: systemImage, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(Color.fmTextSecondary)
                value.font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Color.fmText)
                    .lineLimit(lineLimit).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(FM.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.fmCanvas.opacity(0.6), in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
    }
}

extension Array where Element == MyGameEntry {
    /// Game chưa kết thúc (luật "1 người, 1 game" nên có tối đa 1).
    var activeHunt: MyGameEntry? { first { !$0.game.status.isFinished } }
}

struct JoinGameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State var initialCode: String
    let onJoined: (UUID) -> Void
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Nhập mã tham gia gồm 6 ký tự do quản trò cung cấp.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextField("ABC123", text: $code)
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .tracking(6)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: code) { _, new in
                        let cleaned = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if cleaned != new { code = cleaned }
                    }
                    .padding()
                    .background(Color.fmSunken, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(Text("Mã tham gia"))
                Button {
                    Task { await join() }
                } label: {
                    Group { if working { ProgressView().tint(.fmOnTreasure) } else { Text("Tham gia") } }
                }
                .buttonStyle(.fmPrimary)
                .disabled(code.count != 6 || working)
                Spacer()
            }
            .padding()
            .navigationTitle("Tham gia game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { close() } } }
            .onAppear {
                code = initialCode
                focused = initialCode.isEmpty
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private func close() {
        router.pendingJoinCode = nil
        dismiss()
    }

    private func join() async {
        working = true
        defer { working = false }
        do {
            let id = try await API.joinGame(code: code)
            router.pendingJoinCode = nil
            PushManager.shared.requestAuthorizationIfNeeded()
            dismiss()
            onJoined(id)
        } catch {
            self.error = AppError.message(for: error)
        }
    }
}
