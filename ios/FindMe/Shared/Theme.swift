import SwiftUI
import UIKit

// MARK: - Find Me! design system — "giấy bản đồ" beige
//
// Màu (sáng / tối) nằm trong Assets.xcassets/Theme; mọi cặp chữ/nền đạt WCAG AA (≥ 4.5:1),
// trừ `fmMuted` (≥ 3:1) chỉ dùng cho icon và chip trạng thái phụ.
//
// | Token          | Sáng     | Tối      | Dùng cho                                   |
// |----------------|----------|----------|--------------------------------------------|
// | fmCanvas       | #F4EDE2  | #1B1610  | nền màn hình                               |
// | fmSurface      | #FBF7F0  | #262019  | card, dòng List/Form                       |
// | fmSunken       | #EADFCD  | #322A21  | ô nhập, khối phụ, placeholder ảnh          |
// | fmBorder       | #DCCBB2  | #45392C  | viền card, đường kẻ                        |
// | fmText         | #2B2116  | #F3E9DB  | chữ chính                                  |
// | fmTextSecondary| #6B5A45  | #BFAF98  | chữ phụ                                    |
// | AccentColor    | #8B5A2B  | #D8B07F  | "mực": tint hệ thống, logo, nút phụ, icon  |
// | fmTreasure     | #C2410C  | #FF8A3D  | "kho báu": nút chính, đang diễn ra, tiền   |
// | fmOnTreasure   | #FFFFFF  | #24190E  | chữ trên nền treasure (5.2:1 / 7.3:1)      |
// | fmAccentSoft   | #EBD9BF  | #4A3926  | nền nhấn nhẹ (dòng của tôi, chip)          |
// | fmOnAccent     | #FFFFFF  | #24190E  | chữ trên nền accent                        |
// | fmSuccess/Warning/Danger/Info/Muted     | trạng thái                                 |
//
// Quy tắc 60-30-10: ~60% nền giấy, ~30% mực + chữ, ~10% treasure. Treasure chỉ dành cho
// hành động chính và những thứ "đang nóng" (live, tiền thưởng); dùng nhiều sẽ mất tác dụng.

extension Color {
    static let fmCanvas = Color("Canvas")
    static let fmSurface = Color("Surface")
    static let fmSunken = Color("Sunken")
    static let fmBorder = Color("Border")
    static let fmText = Color("Text")
    static let fmTextSecondary = Color("TextSecondary")
    static let fmAccent = Color("AccentColor")
    static let fmAccentSoft = Color("AccentSoft")
    static let fmOnAccent = Color("OnAccent")
    static let fmTreasure = Color("Treasure")
    static let fmOnTreasure = Color("OnTreasure")
    static let fmSuccess = Color("Success")
    static let fmWarning = Color("Warning")
    static let fmDanger = Color("Danger")
    static let fmInfo = Color("Info")
    static let fmMuted = Color("Muted")
}

// Cho phép viết `.foregroundStyle(.fmAccent)` / `.background(.fmSurface)`.
extension ShapeStyle where Self == Color {
    static var fmCanvas: Color { .fmCanvas }
    static var fmSurface: Color { .fmSurface }
    static var fmSunken: Color { .fmSunken }
    static var fmBorder: Color { .fmBorder }
    static var fmText: Color { .fmText }
    static var fmTextSecondary: Color { .fmTextSecondary }
    static var fmAccent: Color { .fmAccent }
    static var fmAccentSoft: Color { .fmAccentSoft }
    static var fmOnAccent: Color { .fmOnAccent }
    static var fmTreasure: Color { .fmTreasure }
    static var fmOnTreasure: Color { .fmOnTreasure }
    static var fmSuccess: Color { .fmSuccess }
    static var fmWarning: Color { .fmWarning }
    static var fmDanger: Color { .fmDanger }
    static var fmInfo: Color { .fmInfo }
    static var fmMuted: Color { .fmMuted }
}

// MARK: - Typography
//
// Cả app dùng MỘT họ font: SF Pro (font hệ thống). Không dùng serif / mono / rounded; khác biệt chỉ
// nằm ở cỡ chữ và độ đậm. Ngoại lệ duy nhất: chữ logo `FMWordmark` (Brand.swift).
//
// | Vai      | Font                          | Dùng cho                                       |
// |----------|-------------------------------|------------------------------------------------|
// | Display  | SF Pro bold, largeTitle       | tiêu đề lớn, màn chiến thắng                   |
// | Title    | SF Pro bold/semibold          | tên game, tiêu đề hint, tiêu đề section    |
// | Body/UI  | SF Pro (mặc định)             | nội dung, nút, danh sách                       |
// | Số / mã  | SF Pro + `.monospacedDigit()` | mã proof, mã tham gia, đồng hồ, tiền thưởng    |
// | Caps     | SF Pro semibold, hoa          | nhãn nhỏ kiểu "HINT 3", eyebrow                |
// Tất cả theo Dynamic Type. Tiêu đề nhiều dòng dùng `.fmTitleLines()` để dấu tiếng Việt
// chồng (Ể, Ỗ…) không chạm dòng trên.

extension Font {
    static let fmDisplay = Font.system(.largeTitle).weight(.bold)
    static let fmTitle = Font.system(.title2).weight(.bold)
    static let fmTitle3 = Font.system(.title3).weight(.semibold)
    static let fmHeadline = Font.system(.headline)
    /// Mã proof / mã tham gia: dùng kèm `.fmCodeStyle()` để giãn chữ.
    static let fmCode = Font.system(.title).weight(.bold).monospacedDigit()
    /// Số tiền, điểm, thời gian trong dòng: chữ số đều nhau, không nhảy khi đổi giá trị.
    static let fmNumber = Font.system(.subheadline).weight(.semibold).monospacedDigit()
    static let fmCaps = Font.system(.caption).weight(.semibold)
}

// MARK: - Spacing / radius (lưới 4pt)

enum FM {
    // Thang khoảng cách: chỉ dùng các bậc này.
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let pad: CGFloat = 16      // = l
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    /// Lề trái/phải của màn hình.
    static let screen: CGFloat = 20

    static let radiusSmall: CGFloat = 10   // chip, ô nhập
    static let radius: CGFloat = 16        // card, nút
    static let radiusLarge: CGFloat = 24   // thẻ nổi, sheet

    /// Nút chính cao hơn chuẩn 44pt: người chơi vừa đi vừa bấm ngoài trời.
    static let buttonHeight: CGFloat = 56
}

// MARK: - Modifiers

extension View {
    /// Nền giấy kẻ lưới (FMGridBackground) cho List / Form / ScrollView.
    func fmScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .listSectionSpacing(.compact)
            .contentMargins(.top, FM.s, for: .scrollContent)
            .contentMargins(.horizontal, FM.screen, for: .scrollContent)
            .background(FMGridBackground())
    }

    /// Card giấy: nền surface, viền mảnh, bo 16.
    func fmCard(padding: CGFloat = FM.pad) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
    }

    /// Khối nhấn nhẹ (thông tin, đếm ngược…).
    func fmCallout(_ tint: Color = .fmAccent) -> some View {
        self.padding(FM.m)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: FM.radiusSmall, style: .continuous))
            .foregroundStyle(tint)
    }
}

extension View {
    /// Mã proof / mã tham gia: chữ số đều, giãn chữ để không nhầm O/0, I/1.
    func fmCodeStyle() -> some View {
        self.font(.fmCode).tracking(2).monospacedDigit()
    }

    /// Tiêu đề serif nhiều dòng: thêm khoảng cách dòng cho dấu tiếng Việt.
    func fmTitleLines() -> some View {
        self.lineSpacing(3)
    }
}

/// Bọc nội dung List/Form để mọi dòng dùng nền `fmSurface` thay cho trắng/xám hệ thống.
struct ThemedRows<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Group { content }.listRowBackground(Color.fmSurface)
    }
}

/// Đường kẻ chấm kiểu bản đồ kho báu với dấu X ở giữa.
struct TreasureDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            dashed
            Image(systemName: "xmark").font(.caption.weight(.heavy)).foregroundStyle(Color.fmAccent)
            dashed
        }
        .accessibilityHidden(true)
    }
    private var dashed: some View {
        Line().stroke(Color.fmBorder, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
            .frame(height: 2)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

// MARK: - Button styles

struct FMPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: FM.buttonHeight)
            .padding(.horizontal, FM.pad)
            .foregroundStyle(Color.fmOnTreasure)
            .background(Color.fmTreasure.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
            .shadow(color: Color.fmTreasure.opacity(isEnabled && !configuration.isPressed ? 0.28 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct FMSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: FM.buttonHeight)
            .padding(.horizontal, FM.pad)
            .foregroundStyle(Color.fmAccent.opacity(isEnabled ? 1 : 0.4))
            .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FM.radius, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Nút chính dạng gọn (chỉ rộng bằng nội dung): đứng cạnh ô nhập, trên màn camera…
struct FMCompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .frame(minHeight: 50)
            .padding(.horizontal, FM.xl)
            .foregroundStyle(Color.fmOnTreasure)
            .background(Color.fmTreasure.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: FM.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FMPrimaryButtonStyle { static var fmPrimary: FMPrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == FMCompactPrimaryButtonStyle { static var fmPrimaryCompact: FMCompactPrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == FMSecondaryButtonStyle { static var fmSecondary: FMSecondaryButtonStyle { .init() } }

// MARK: - UIKit appearance (thanh điều hướng, tab bar)

enum Theme {
    @MainActor static func applyAppearance() {
        let text = UIColor(named: "Text") ?? .label
        let surface = UIColor(named: "Surface") ?? .secondarySystemBackground
        let accent = UIColor(named: "AccentColor") ?? .tintColor
        let muted = UIColor(named: "TextSecondary") ?? .secondaryLabel
        let border = UIColor(named: "Border") ?? .separator

        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let desc = UIFont.systemFont(ofSize: base.pointSize, weight: weight).fontDescriptor
            let font = desc.withDesign(.serif).map { UIFont(descriptor: $0, size: base.pointSize) }
                ?? UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }

        // Nền trong suốt: màn hình đã có nền beige. (Nền opaque che mất large title trên iOS 26.)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: text, .font: serif(.headline, .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: serif(.largeTitle, .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = surface
        tab.shadowColor = border
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.foregroundColor: muted]
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [.foregroundColor: accent]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UISegmentedControl.appearance().selectedSegmentTintColor = accent
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(named: "OnAccent") ?? .white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: text], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(named: "Sunken")
    }
}
