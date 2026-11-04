import MapKit
import SwiftUI

/// Tab "MAP": mọi game công khai (+ của mình) trên bản đồ 3D. Thu nhỏ hết cỡ thành quả địa cầu.
/// Marker gom cụm theo mức zoom, tô màu theo trạng thái; game đang diễn ra nhấp nháy.
/// Không bao giờ hiện mã tham gia (get_globe_games không trả về).
struct GlobeView: View {
    let open: (UUID) -> Void
    let join: () -> Void

    enum Filter: Hashable, CaseIterable { case all, live, scheduled, completed, mine }

    @State private var games: [GlobeGame] = []
    @State private var activeTitle: String?
    @State private var loaded = false
    @State private var error: String?
    @State private var filter: Filter = .all
    @State private var satellite = false
    // Không dùng .automatic: MapKit canh lại khung mỗi khi marker đổi → camera đổi → gom cụm lại
    // → marker đổi… vòng lặp làm đứng app. Khung được tính tay từ dữ liệu (fitRegion).
    @State private var position: MapCameraPosition = .region(GlobeView.defaultRegion)
    /// Mức zoom rời rạc (log2 của chiều cao vùng xem). Chỉ đổi khi zoom đủ nhiều, nên kéo/xoay
    /// bản đồ không làm gom cụm lại.
    @State private var zoomLevel = -3
    @State private var cameraCenter = GlobeView.defaultRegion.center
    @State private var didFrameData = false
    @State private var selected: GlobeGame?

    /// Khoảng cách camera đủ xa để thấy cả quả địa cầu.
    private static let globeDistance: CLLocationDistance = 22_000_000
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15))

    private var visible: [GlobeGame] {
        switch filter {
        case .all: games
        case .live: games.filter { $0.status == .live }
        case .scheduled: games.filter { $0.status == .scheduled }
        case .completed: games.filter { $0.status == .completed }
        case .mine: games.filter { $0.myRole != nil }
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(clusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        Button { tap(cluster) } label: { ClusterMarker(cluster: cluster) }
                            .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                                : .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapPitchToggle(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraCenter = context.region.center
                let level = Self.zoomLevel(for: context.region.span.latitudeDelta)
                if level != zoomLevel { zoomLevel = level }
            }
            .safeAreaInset(edge: .top) { filterBar }
            .overlay(alignment: .bottomLeading) { summary }
            .overlay(alignment: .bottomTrailing) { controls }
            .fmTabBarInset()
            .overlay { if !loaded { ProgressView().controlSize(.large) } }
            .navigationTitle("MAP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(Text("Tải lại"))
                }
            }
            .task { if !loaded { await load() } }
            .sheet(item: $selected) { game in
                GlobeGameCard(game: game, blockedBy: activeTitle,
                              open: { selected = nil; open(game.id) },
                              join: { selected = nil; join() })
                    .presentationDetents([.height(340), .medium])
                    .presentationBackground(Color.fmCanvas)
            }
            .errorAlert($error)
        }
    }

    // MARK: Overlays

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { withAnimation(.snappy) { filter = f } } label: {
                        HStack(spacing: 6) {
                            if let color = f.color { Circle().fill(color).frame(width: 8, height: 8) }
                            Text(f.label)
                            Text("\(count(f))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(filter == f ? Color.fmAccentSoft : Color.fmSurface.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(filter == f ? Color.fmAccent : Color.fmBorder, lineWidth: 1))
                        .foregroundStyle(Color.fmText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.horizontal, FM.pad).padding(.vertical, 8)
        }
    }

    private var summary: some View {
        let live = visible.filter { $0.status == .live }.count
        return Text("\(visible.count) game · \(live) đang diễn ra")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            mapButton("globe.asia.australia.fill", label: "Xem toàn cầu") {
                withAnimation(.easeInOut(duration: 1.6)) {
                    position = .camera(MapCamera(centerCoordinate: cameraCenter, distance: Self.globeDistance))
                }
            }
            mapButton("scope", label: "Xem tất cả game") { fitAll() }
            mapButton(satellite ? "map" : "globe.americas", label: satellite ? "Bản đồ thường" : "Ảnh vệ tinh") {
                satellite.toggle()
            }
        }
        .padding(12)
        .padding(.bottom, 28)
    }

    private func mapButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: Clustering

    static func zoomLevel(for latitudeDelta: Double) -> Int {
        // Ở chế độ quả địa cầu MapKit có thể trả span NaN/vô hạn; Int(NaN) sẽ crash.
        guard latitudeDelta.isFinite, latitudeDelta > 0 else { return 7 }
        return Int(log2(max(latitudeDelta, 0.001)).rounded(.down)).clamped(to: -10...7)
    }

    /// Gom marker theo ô lưới ≈ 1/6 chiều cao vùng đang xem (theo mức zoom rời rạc), nên càng thu
    /// nhỏ càng gom nhiều. Id cụm = id game nhỏ nhất + số lượng, ổn định giữa các lần vẽ.
    private var clusters: [GlobeCluster] {
        let cell = pow(2, Double(zoomLevel)) / 6
        var buckets: [String: [GlobeGame]] = [:]
        for g in visible {
            let key = "\(Int((g.areaLat / cell).rounded(.down))):\(Int((g.areaLng / cell).rounded(.down)))"
            buckets[key, default: []].append(g)
        }
        return buckets.values.map { members in
            let sorted = members.sorted { $0.id.uuidString < $1.id.uuidString }
            return GlobeCluster(id: "\(sorted[0].id.uuidString)-\(sorted.count)", games: sorted)
        }
        .sorted { $0.games.count < $1.games.count }
    }

    /// Khung bao các game đang lọc (đệm 40%), tối thiểu ~5 km.
    private var fitRegion: MKCoordinateRegion? {
        guard !visible.isEmpty else { return nil }
        let lats = visible.map(\.areaLat), lngs = visible.map(\.areaLng)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lngs.min()! + lngs.max()!) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: min(max((lats.max()! - lats.min()!) * 1.4, 0.05), 150),
                                                         longitudeDelta: min(max((lngs.max()! - lngs.min()!) * 1.4, 0.05), 300)))
    }

    private func tap(_ cluster: GlobeCluster) {
        if cluster.games.count == 1 {
            selected = cluster.games[0]
            return
        }
        let lats = cluster.games.map(\.areaLat), lngs = cluster.games.map(\.areaLng)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.8, 0.01),
                                    longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.8, 0.01))
        withAnimation(.easeInOut(duration: 1.0)) {
            position = .region(MKCoordinateRegion(center: cluster.coordinate, span: span))
        }
    }

    private func fitAll() {
        guard let fitRegion else { return }
        withAnimation(.easeInOut(duration: 1.2)) { position = .region(fitRegion) }
    }

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: games.count
        case .live: games.filter { $0.status == .live }.count
        case .scheduled: games.filter { $0.status == .scheduled }.count
        case .completed: games.filter { $0.status == .completed }.count
        case .mine: games.filter { $0.myRole != nil }.count
        }
    }

    private func load() async {
        do {
            async let mine = API.myGames()
            games = try await API.globeGames()
            activeTitle = (try? await mine)?.activeHunt?.game.title
            loaded = true
            // Lần đầu có dữ liệu: canh khung vào các game (một lần, không theo dõi liên tục).
            if !didFrameData, let fitRegion {
                didFrameData = true
                position = .region(fitRegion)
                zoomLevel = Self.zoomLevel(for: fitRegion.span.latitudeDelta)
            }
        } catch {
            loaded = true
            if !Task.isCancelled { self.error = AppError.message(for: error) }
        }
    }
}

extension GlobeView.Filter {
    var label: LocalizedStringKey {
        switch self {
        case .all: "Tất cả"
        case .live: "Đang diễn ra"
        case .scheduled: "Sắp diễn ra"
        case .completed: "Đã kết thúc"
        case .mine: "Của tôi"
        }
    }
    var color: Color? {
        switch self {
        case .all, .mine: nil
        case .live: GameStatus.live.color
        case .scheduled: GameStatus.scheduled.color
        case .completed: GameStatus.completed.color
        }
    }
}

struct GlobeCluster: Identifiable {
    let id: String
    let games: [GlobeGame]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: games.map(\.areaLat).reduce(0, +) / Double(games.count),
                               longitude: games.map(\.areaLng).reduce(0, +) / Double(games.count))
    }
    var hasLive: Bool { games.contains { $0.status == .live } }

    /// Hệ số kích thước pin theo giải tổng (VND): từ 1.000.000 trở xuống là 1×, mỗi 2.000.000 thêm
    /// vào thì to thêm 0,2× (3.000.000 → 1,2×; 5.000.000 → 1,4×…), tối đa 2× (từ 11.000.000).
    /// Game dùng tiền tệ khác giữ 1×.
    static func prizeScale(_ game: GlobeGame) -> CGFloat {
        guard game.currency.uppercased() == "VND", game.grandPrize > base else { return 1 }
        let steps = ((game.grandPrize - base) / step).rounded(.down)
        return min(1 + CGFloat(steps) * 0.2, maxScale)
    }
    private static let base: Double = 1_000_000
    private static let step: Double = 2_000_000
    private static let maxScale: CGFloat = 2
    /// Màu cụm: đang diễn ra > sắp diễn ra > đã kết thúc.
    var color: Color {
        if hasLive { return GameStatus.live.color }
        if games.contains(where: { $0.status == .scheduled }) { return GameStatus.scheduled.color }
        return games[0].status.color
    }
}

private struct ClusterMarker: View {
    let cluster: GlobeCluster

    var body: some View {
        let n = cluster.games.count
        // Pin lẻ to theo giải thưởng; cụm to theo số game.
        let scale = n == 1 ? GlobeCluster.prizeScale(cluster.games[0]) : 1
        let size: CGFloat = n == 1 ? 22 * scale : min(30 + sqrt(CGFloat(n)) * 8, 72)
        ZStack {
            if cluster.hasLive {
                Circle()
                    .fill(cluster.color.opacity(0.35))
                    .frame(width: size, height: size)
                    .phaseAnimator([1.0, 1.9]) { content, scale in
                        content.scaleEffect(scale).opacity(2 - scale)
                    } animation: { _ in .easeOut(duration: 1.4) }
            }
            Circle()
                .fill(cluster.color.gradient)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            if n > 1 {
                Text("\(n)").font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            } else if cluster.games[0].myRole != nil {
                Image(systemName: "star.fill").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(.white)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(n == 1 ? Text(cluster.games[0].title) : Text("\(n) game"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Thẻ chi tiết một game (Globe và danh sách Game).
struct GlobeGameCard: View {
    let game: GlobeGame
    /// Tên game chưa kết thúc mà mình đang ở trong (luật "1 người, 1 game"), nếu có.
    var blockedBy: String?
    let open: () -> Void
    let join: () -> Void
    @State private var joining = false
    @State private var error: String?

    private var isOpenJoin: Bool {
        game.joinOpen == true && (game.status == .live || game.status == .scheduled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(game.title).font(.fmTitle).foregroundStyle(Color.fmText)
                Spacer()
                StatusChip(text: game.status.label, color: game.status.color)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let area = game.areaName {
                    Label(area, systemImage: "mappin.and.ellipse")
                }
                Label { Emphasis.keyword("Quản trò:", game.hostName) } icon: {
                    AvatarView(path: game.hostAvatarPath, name: game.hostName, size: 20)
                }
                Label { Emphasis.counts([(game.playerCount, "người chơi"), (game.hintCount, "hint")]) } icon: {
                    Image(systemName: "person.3")
                }
                if let prize = Fmt.prize(game.grandPrize, item: game.grandPrizeItem, currency: game.currency) {
                    Label(prize, systemImage: "gift")
                }
                if let when = timeText {
                    Label { when } icon: { Image(systemName: "clock") }
                }
                if game.joinOpen == true {
                    Label("Mở cho mọi người, không cần mã", systemImage: "door.left.hand.open")
                }
            }
            .font(.subheadline).foregroundStyle(Color.fmTextSecondary)

            if game.myRole != nil {
                Button("Mở game", action: open).buttonStyle(.fmPrimary)
            } else if game.status == .completed {
                Text("Game đã kết thúc.").font(.footnote).foregroundStyle(.secondary)
            } else if let blockedBy {
                Label {
                    // Tên game in đậm (và màu chữ chính) để nổi lên giữa câu chữ phụ.
                    Text("Bạn đang ở trong \"\(Text(blockedBy).bold().foregroundStyle(Color.fmText))\". Mỗi người chỉ tham gia 1 game tại một thời điểm.")
                } icon: { Image(systemName: "lock.fill") }
                .font(.footnote).foregroundStyle(Color.fmTextSecondary)
            } else if isOpenJoin {
                Button(action: joinNow) {
                    HStack(spacing: FM.s) {
                        if joining { ProgressView() }
                        Text("Tham gia ngay")
                    }
                }
                .buttonStyle(.fmPrimary)
                .disabled(joining)
            } else {
                Text("Xin mã 6 ký tự từ quản trò để tham gia.").font(.footnote).foregroundStyle(.secondary)
                Button("Nhập mã tham gia", action: join).buttonStyle(.fmSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .errorAlert($error)
    }

    private func joinNow() {
        joining = true
        Task {
            defer { joining = false }
            do {
                _ = try await API.joinOpenGame(gameId: game.id)
                open()
            } catch { self.error = AppError.message(for: error) }
        }
    }

    private var timeText: Text? {
        switch game.status {
        case .scheduled: game.startsAt.map { Emphasis.keyword("Bắt đầu:", Fmt.dateTime($0)) }
        case .live: game.startedAt.map { Emphasis.keyword("Bắt đầu lúc:", Fmt.dateTime($0)) }
        case .completed: game.endedAt.map { Emphasis.keyword("Kết thúc:", Fmt.dateTime($0)) }
        default: nil
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
