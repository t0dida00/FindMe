import SwiftUI

/// Bottom navigation sau khi đăng nhập: Game · MAP · Xếp hạng · ME, bằng thanh tab nổi
/// (FMFloatingTabBar) thay cho tab bar hệ thống. Tab nào đã mở thì giữ nguyên trạng thái (ẩn bằng opacity).
/// Sheet nhập mã tham gia mở từ nút "Tham gia" ở tab Game, thẻ chi tiết game, hoặc deep link.
struct MainTabView: View {
    enum MainTab: Hashable { case games, globe, rankings, profile }

    @Environment(AppRouter.self) private var router
    @State private var tab: MainTab = .games
    @State private var showJoin = false
    @State private var presentedGame: PresentedGame?
    /// Game mở từ lịch sử ở tab ME: đẩy vào từ phải, có nút quay lại, đóng thì vẫn ở ME.
    @State private var pushedGame: PresentedGame?
    @State private var reloadTick = 0
    @State private var visited: Set<MainTab> = [.games]
    /// Đang ở trong một game chưa kết thúc (người chơi hoặc quản trò): huy hiệu "1" trên tab Game.
    @State private var inActiveGame = false

    private var items: [FMTabItem<MainTab>] { [
        .init(tag: .games, title: "Game", systemImage: "map", badge: inActiveGame ? 1 : 0),
        .init(tag: .globe, title: "MAP", systemImage: "globe.asia.australia"),
        .init(tag: .rankings, title: "Xếp hạng", systemImage: "trophy"),
        .init(tag: .profile, title: "ME", systemImage: "person"),
    ] }

    struct PresentedGame: Identifiable, Hashable { let id: UUID }

    var body: some View {
        ZStack {
            page(.games) {
                HomeView(open: open, join: { showJoin = true }, showProfile: { tab = .profile }, reloadTick: reloadTick,
                         activeChanged: { inActiveGame = $0 })
            }
            page(.globe) { GlobeView(open: open, join: { showJoin = true }) }
            page(.rankings) { RankingsView() }
            page(.profile) { ProfileView(open: push, reloadTick: reloadTick) }
        }
        // Thanh tab đè lên trên; mỗi màn tự chừa chỗ bằng `fmTabBarInset()`.
        .overlay(alignment: .bottom) {
            FMFloatingTabBar(items: items, selection: $tab)
        }
        // Game "push" (từ lịch sử) phủ lên cả thanh tab, giống màn được đẩy vào NavigationStack.
        .overlay {
            if let g = pushedGame {
                GameScreen(gameId: g.id, onBack: popGame)
                    .background(Color.fmCanvas.ignoresSafeArea())
                    .id(g.id)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: tab, initial: true) { _, t in visited.insert(t) }
        .sheet(isPresented: $showJoin) {
            JoinGameSheet(initialCode: router.pendingJoinCode ?? "") { id in open(id) }
        }
        .fullScreenCover(item: $presentedGame, onDismiss: { reloadTick += 1 }) { g in
            GameScreen(gameId: g.id)
        }
        .onChange(of: router.pendingJoinCode, initial: true) { _, code in
            if code != nil { presentedGame = nil; showJoin = true }
        }
        .onChange(of: router.openGameId, initial: true) { _, id in
            if let id { open(id); router.openGameId = nil }
        }
    }

    /// Chỉ dựng tab khi đã mở lần đầu; sau đó giữ sống để không mất vị trí cuộn, bộ lọc…
    @ViewBuilder private func page<Content: View>(_ t: MainTab, @ViewBuilder _ content: () -> Content) -> some View {
        if visited.contains(t) {
            let shown = tab == t
            content()
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
        }
    }

    private func open(_ id: UUID) {
        showJoin = false
        pushedGame = nil
        tab = .games
        presentedGame = PresentedGame(id: id)
    }

    /// Mở game mà không đổi tab (lịch sử ở ME): trượt vào từ phải, quay lại thì về đúng chỗ cũ.
    private func push(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.3)) { pushedGame = PresentedGame(id: id) }
    }

    private func popGame() {
        withAnimation(.easeOut(duration: 0.25)) { pushedGame = nil }
        reloadTick += 1
    }
}
