import SwiftUI

// MARK: - Bố cục chung: nền lưới, tab bar nổi, nhóm dòng có ô icon, ô thẻ lưới
//
// | Thành phần          | Dùng cho                                                          |
// |---------------------|-------------------------------------------------------------------|
// | FMGridBackground    | nền mọi màn (qua `fmScreen()`): giấy + lưới ô vuông mờ            |
// | FMFloatingTabBar    | thanh tab nổi bo tròn ở đáy (MainTabView, GameScreen)             |
// | FMIconTile          | ô vuông bo góc chứa icon, nền nhạt cùng màu icon                   |
// | FMGroup + FMRow     | nhóm dòng kiểu cài đặt: icon · tiêu đề/phụ đề · giá trị · ›        |
// | FMSectionLabel      | nhãn nhỏ phía trên một nhóm                                       |
// | FMTile              | ô thẻ lớn trong lưới 2 cột: icon lớn, nhãn bên dưới               |
// | FMTileGrid          | lưới 2 cột cho FMTile: các ô bằng rộng, cùng hàng thì bằng cao    |
// | FMPillButton        | nút viên thuốc nhỏ trên header ("Tham gia", "Sửa")                |
// | FMScrollScreen      | khung chuẩn cho màn cuộn: lề 20 (FM.screen), giãn FM.m, đáy FM.xl  |
// | FMPushedHeader      | header màn được push (ẩn nav bar): ô ← · ô tiêu đề có icon        |
// Màu vẫn theo Theme.swift: icon/viền dùng mực `fmAccent`, cam `fmTreasure` chỉ cho thứ "nóng".

/// Giấy bản đồ có lưới ô vuông mờ.
struct FMGridBackground: View {
    var spacing: CGFloat = 28

    var body: some View {
        Color.fmCanvas
            .overlay {
                Canvas { ctx, size in
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += spacing }
                    var y: CGFloat = 0
                    while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += spacing }
                    ctx.stroke(path, with: .color(Color.fmBorder.opacity(0.45)), lineWidth: 0.5)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: Tab bar

struct FMTabItem<Tag: Hashable>: Identifiable {
    let tag: Tag
    let title: LocalizedStringKey
    let systemImage: String
    /// Số trên huy hiệu ở góc icon (vd. proof chờ duyệt); 0 thì ẩn.
    var badge: Int = 0
    var id: Tag { tag }
}

/// Thanh tab nổi: khối bo tròn trên nền surface; tab đang chọn có ô nhấn viền mực.
struct FMFloatingTabBar<Tag: Hashable>: View {
    let items: [FMTabItem<Tag>]
    @Binding var selection: Tag
    @Namespace private var ns

    var body: some View {
        HStack(spacing: FM.xs) {
            ForEach(items) { item in
                let selected = item.tag == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.tag }
                } label: {
                    VStack(spacing: FM.xs) {
                        Image(systemName: item.systemImage).font(.system(size: 19, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if item.badge > 0 {
                                    Text(verbatim: item.badge > 99 ? "99+" : "\(item.badge)")
                                        .font(.caption2.weight(.bold)).monospacedDigit()
                                        .foregroundStyle(Color.fmOnTreasure)
                                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                        .background(Color.fmTreasure, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.fmSurface, lineWidth: 2))
                                        .offset(x: 12, y: -8)
                                }
                            }
                        Text(item.title)
                            // 10pt: nhỏ hơn fmCaps (12pt) 2pt cho thanh tab gọn hơn.
                            .font(.system(size: 10, weight: .semibold)).textCase(.uppercase).tracking(0.8)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selected ? Color.fmAccent : Color.fmTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: FM.radius, style: .continuous)
                                .fill(Color.fmAccentSoft)
                                .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous)
                                    .strokeBorder(Color.fmAccent.opacity(0.55), lineWidth: 1.5))
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(FM.s)
        .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radiusLarge + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge + 4, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, FM.screen)
        // Lấn xuống vùng home indicator một chút cho sát đáy (vẫn chừa vạch home).
        .padding(.bottom, -FM.s)
    }
}

extension View {
    /// Chừa chỗ cho thanh tab nổi ở đáy. Đặt BÊN TRONG NavigationStack của mỗi màn thuộc tab
    /// (cả màn được push), vì safe area từ ngoài không truyền qua NavigationStack.
    func fmTabBarInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: FM.tabBarHeight) }
    }
}

// MARK: Scroll screen

/// Khung chuẩn của mọi màn dạng cuộn (giống tab Game): lề ngang `FM.screen` (20) và lề trên `FM.s`
/// từ `fmScreen()`, các khối cách nhau `FM.m`, chừa `FM.xl` ở đáy. Không thêm `.padding()` vào nội dung.
struct FMScrollScreen<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = FM.m
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: alignment, spacing: spacing) { content }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
                .padding(.bottom, FM.xl)
        }
        .fmScreen()
    }
}

// MARK: Pushed header

/// Header cho màn được push mà ẩn navigation bar: ô vuông "←" bên trái, ô tiêu đề có icon chiếm phần còn lại.
/// Màn dùng nó cần `.toolbar(.hidden, for: .navigationBar)`; vuốt từ mép trái để quay lại vẫn hoạt động
/// (xem extension UINavigationController bên dưới).
struct FMPushedHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: FM.m) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.fmText)
                    .frame(width: FM.buttonHeight, height: FM.buttonHeight)
                    .background(box)
            }
            .buttonStyle(FMTilePressStyle())
            .accessibilityLabel(Text("Quay lại"))

            HStack(spacing: FM.m) {
                FMIconTile(systemImage: systemImage, size: 40)
                Text(title).font(.headline).foregroundStyle(Color.fmText).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FM.s)
            .frame(maxWidth: .infinity, minHeight: FM.buttonHeight)
            .background(box)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, FM.s)
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
            .fill(Color.fmSurface)
            .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
    }
}

/// Giữ cử chỉ vuốt mép trái để quay lại khi màn ẩn navigation bar.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: Icon tile

struct FMIconTile: View {
    let systemImage: String
    var tint: Color = .fmAccent
    var size: CGFloat = 44
    /// true: nền đặc, icon chữ trắng/onAccent (ô icon lớn trên FMTile).
    var filled = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(filled ? Color.fmOnAccent : tint)
            .frame(width: size, height: size)
            .background(filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: Group + row

struct FMSectionLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.fmTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, FM.s)
            .padding(.top, FM.m)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Khối bo góc lớn chứa các FMRow; đặt `FMGroupDivider()` giữa các dòng.
struct FMGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
    }
}

struct FMGroupDivider: View {
    var body: some View { Rectangle().fill(Color.fmBorder).frame(height: 1) }
}

/// Dòng: ô icon · tiêu đề (+ phụ đề) · giá trị · ›. `action == nil` thì là dòng tĩnh.
struct FMRow<Trailing: View>: View {
    let systemImage: String
    var tint: Color = .fmAccent
    let title: Text
    var subtitle: Text?
    var titleColor: Color = .fmText
    var chevron = true
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(FMRowPressStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: FM.m + 2) {
            FMIconTile(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline).foregroundStyle(titleColor)
                if let subtitle {
                    subtitle.font(.subheadline).foregroundStyle(Color.fmTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            Spacer(minLength: FM.s)
            trailing
            if chevron && action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold)).foregroundStyle(Color.fmTextSecondary)
            }
        }
        .padding(.horizontal, FM.pad)
        .padding(.vertical, FM.m)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }
}

extension FMRow where Trailing == EmptyView {
    init(systemImage: String, tint: Color = .fmAccent, title: Text, subtitle: Text? = nil,
         titleColor: Color = .fmText, chevron: Bool = true, action: (() -> Void)? = nil) {
        self.init(systemImage: systemImage, tint: tint, title: title, subtitle: subtitle,
                  titleColor: titleColor, chevron: chevron, action: action) { EmptyView() }
    }
}

struct FMRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.fmSunken.opacity(configuration.isPressed ? 0.8 : 0))
    }
}

// MARK: Tile

/// Ô thẻ lớn trong lưới 2 cột: ô icon to (có thể kèm huy hiệu), nhãn và dòng phụ bên dưới.
/// Ảnh đại diện để vẽ bằng AvatarView (path trong bucket `avatars`, tên để ra chữ cái đầu khi chưa có ảnh).
struct FMAvatarRef: Hashable, Sendable {
    let path: String?
    let name: String
}

struct FMTile<Badge: View>: View {
    let systemImage: String
    var tint: Color = .fmAccent
    let title: Text
    var subtitle: Text?
    /// Có thì vẽ avatar nhỏ trước subtitle (vd. quản trò của game).
    var subtitleAvatar: FMAvatarRef? = nil
    /// Các dòng phụ dưới subtitle (mỗi dòng 1 hàng), vd. quản trò · giờ bắt đầu.
    var details: [Text] = []
    let action: () -> Void
    @ViewBuilder var badge: Badge

    var body: some View {
        Button(action: action) {
            VStack(spacing: FM.s + 2) {
                FMIconTile(systemImage: systemImage, tint: tint, size: 64, filled: true)
                    .overlay(alignment: .bottomTrailing) { badge.offset(x: 14, y: 8) }
                    .padding(.bottom, FM.xs)
                title.font(.headline).foregroundStyle(Color.fmText)
                    .multilineTextAlignment(.center).lineLimit(2)
                if let subtitle {
                    HStack(spacing: FM.xs + 2) {
                        if let a = subtitleAvatar { AvatarView(path: a.path, name: a.name, size: 18) }
                        subtitle.font(.caption).foregroundStyle(Color.fmTextSecondary)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                }
                ForEach(details.indices, id: \.self) { i in
                    details[i].font(.caption).foregroundStyle(Color.fmTextSecondary)
                        .multilineTextAlignment(.center).lineLimit(1)
                }
            }
            // Lề trong hẹp (8pt) để tên game ngắn như "Hẻm nhỏ Phú Nhuận" vừa 1 dòng trên iPhone 6.1".
            .padding(.horizontal, FM.s)
            .padding(.vertical, FM.m)
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                    .fill(Color.fmSurface)
                    .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)))
            }
            .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
        }
        .buttonStyle(FMTilePressStyle())
    }
}

extension FMTile where Badge == EmptyView {
    init(systemImage: String, tint: Color = .fmAccent, title: Text, subtitle: Text? = nil,
         subtitleAvatar: FMAvatarRef? = nil, details: [Text] = [], action: @escaping () -> Void) {
        self.init(systemImage: systemImage, tint: tint, title: title, subtitle: subtitle,
                  subtitleAvatar: subtitleAvatar, details: details, action: action) { EmptyView() }
    }
}

/// Huy hiệu nhỏ dạng viên thuốc ở góc ô icon (số người chơi…).
struct FMBadge: View {
    let systemImage: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.caption2.weight(.bold))
            Text(verbatim: text).font(.caption.weight(.bold)).monospacedDigit()
        }
        .foregroundStyle(Color.fmText)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.fmSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.fmBorder, lineWidth: 1.5))
    }
}

struct FMTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Pill button

/// Nút viên thuốc trên header: viền mực, nền nhấn nhẹ.
struct FMPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.fmAccent)
            .padding(.horizontal, FM.pad)
            .frame(minHeight: 44)
            .background(Color.fmAccentSoft, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmAccent.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FMPillButtonStyle { static var fmPill: FMPillButtonStyle { .init() } }

extension FM {
    /// Chiều cao thanh tab nổi (tính cả lề), không gồm vùng home indicator.
    static let tabBarHeight: CGFloat = 72
}

/// Lưới 2 cột cho FMTile: mọi ô cùng chiều rộng (nửa màn hình trừ khoảng cách), các ô trong một hàng
/// cùng chiều cao (bằng ô cao nhất), nên thẻ luôn cân đối dù nội dung dài ngắn khác nhau.
struct FMTileGrid: Layout {
    var columns = 2
    var spacing: CGFloat = FM.m

    private func cellWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let heights = rowHeights(subviews, width: cellWidth(width))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = cellWidth(bounds.width)
        let heights = rowHeights(subviews, width: w)
        var y = bounds.minY
        for (row, h) in heights.enumerated() {
            for col in 0..<columns {
                let i = row * columns + col
                guard i < subviews.count else { break }
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(col) * (w + spacing), y: y),
                                  proposal: ProposedViewSize(width: w, height: h))
            }
            y += h + spacing
        }
    }
}
