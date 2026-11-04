import SwiftUI

struct GameScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: GameViewModel
    @State private var connectivity = ConnectivityMonitor.shared
    @State private var playerTab: GameTab = .hint
    @State private var staffTab: GameTab = .manage
    @State private var visited: Set<GameTab> = []

    /// Có thì màn được "đẩy vào" (mở từ lịch sử): nút ‹ quay lại + vuốt từ mép trái thay cho ⌄ đóng.
    private let onBack: (() -> Void)?

    init(gameId: UUID, onBack: (() -> Void)? = nil) {
        _vm = State(initialValue: GameViewModel(gameId: gameId))
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if !vm.isLoaded {
                FMLoadingView(message: "Đang mở game…")
            } else if vm.game == nil || vm.myRole == nil {
                NavigationStack {
                    ContentUnavailableView("Không mở được game",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(vm.loadError ?? String(localized: "Bạn không còn trong game này.")))
                        .gameToolbar(vm: vm, close: close, isPushed: onBack != nil)
                }
            } else if vm.isStaff {
                staffTabs
            } else {
                playerTabs
            }
        }
        .environment(vm)
        .overlay(alignment: .top) {
            if let banner = vm.banner {
                BannerView(text: banner, success: vm.bannerIsSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { vm.banner = nil }
                    .padding(.top, 4)
            }
        }
        .animation(.spring, value: vm.banner)
        .overlay(alignment: .leading) { if onBack != nil { edgeSwipeBack } }
        .sensoryFeedback(.success, trigger: vm.hapticTick)
        .task { await vm.run() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await vm.refresh() } } }
        .onChange(of: connectivity.reconnectTick) { _, _ in Task { await vm.refresh() } }
        .alert("Mã bị từ chối", isPresented: Binding(get: { vm.deniedNotice != nil },
                                                         set: { if !$0 { vm.deniedNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(vm.deniedNotice ?? "") }
    }

    private var close: () -> Void { onBack ?? { dismiss() } }

    /// Vuốt từ mép trái để quay lại (như NavigationStack), chỉ khi màn được đẩy vào.
    private var edgeSwipeBack: some View {
        Color.clear
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.width > 80 && abs(v.translation.height) < 80 { close() }
            })
    }

    // MARK: Tabs (thanh tab nổi giống màn chính)

    enum GameTab: Hashable { case hint, map, leaderboard, info, manage, review, activity }

    private var isFinished: Bool { vm.game?.status.isFinished == true }

    private var playerItems: [FMTabItem<GameTab>] {
        [
            isFinished ? .init(tag: .hint, title: "Kết quả", systemImage: "trophy")
                       : .init(tag: .hint, title: "Hint", systemImage: "lightbulb"),
            .init(tag: .map, title: "Bản đồ", systemImage: "map"),
            .init(tag: .leaderboard, title: "Xếp hạng", systemImage: "list.number"),
            .init(tag: .info, title: "Thông tin", systemImage: "info.circle"),
        ]
    }

    private var staffItems: [FMTabItem<GameTab>] {
        [
            .init(tag: .manage, title: "Quản lý", systemImage: "slider.horizontal.3"),
            .init(tag: .review, title: "Duyệt", systemImage: "checkmark.seal",
                  badge: vm.openSubmissions.filter { $0.status == .pending }.count),
            .init(tag: .activity, title: "Hoạt động", systemImage: "clock.arrow.circlepath"),
            .init(tag: .map, title: "Bản đồ", systemImage: "map"),
            .init(tag: .leaderboard, title: "Xếp hạng", systemImage: "list.number"),
        ]
    }

    private var playerTabs: some View {
        tabs(playerItems, selection: $playerTab) {
            page(.hint, playerTab) { if isFinished { ResultsView() } else { HintTab() } }
            page(.map, playerTab) { JourneyMapView() }
            page(.leaderboard, playerTab) { LeaderboardView() }
            page(.info, playerTab) { PlayerInfoTab(onLeft: close) }
        }
    }

    private var staffTabs: some View {
        tabs(staffItems, selection: $staffTab) {
            page(.manage, staffTab) { ManageTab() }
            page(.review, staffTab) { ReviewTab() }
            page(.activity, staffTab) { ActivityTab() }
            page(.map, staffTab) { JourneyMapView() }
            page(.leaderboard, staffTab) { LeaderboardView() }
        }
    }

    private func tabs<Pages: View>(_ items: [FMTabItem<GameTab>], selection: Binding<GameTab>,
                                   @ViewBuilder pages: () -> Pages) -> some View {
        ZStack { pages() }
            .overlay(alignment: .bottom) { FMFloatingTabBar(items: items, selection: selection) }
            .ignoresSafeArea(.keyboard)
            .onChange(of: selection.wrappedValue, initial: true) { _, t in visited.insert(t) }
    }

    /// Như MainTabView: chỉ dựng tab khi mở lần đầu, sau đó giữ sống (ẩn bằng opacity) để không mất
    /// vị trí cuộn hay màn đã push.
    @ViewBuilder private func page<Content: View>(_ t: GameTab, _ current: GameTab,
                                                  @ViewBuilder _ content: () -> Content) -> some View {
        if visited.contains(t) {
            let shown = current == t
            NavigationStack {
                content().gameToolbar(vm: vm, close: close, isPushed: onBack != nil).fmTabBarInset()
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
        }
    }
}

private struct GameToolbar: ViewModifier {
    let vm: GameViewModel
    let close: () -> Void
    var isPushed = false
    func body(content: Content) -> some View {
        content
            .navigationTitle(vm.game?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: vm.game?.title ?? "")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isPushed {
                        Button { close() } label: { Image(systemName: "chevron.left").fontWeight(.semibold) }
                            .accessibilityLabel(Text("Quay lại"))
                    } else {
                        Button { close() } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel(Text("Đóng game"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Circle().fill(vm.realtimeConnected ? Color.fmSuccess : Color.fmWarning)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(vm.realtimeConnected ? Text("Đang kết nối trực tiếp") : Text("Đang kết nối lại"))
                }
            }
    }
}

extension View {
    func gameToolbar(vm: GameViewModel, close: @escaping () -> Void, isPushed: Bool = false) -> some View {
        modifier(GameToolbar(vm: vm, close: close, isPushed: isPushed))
    }
}
