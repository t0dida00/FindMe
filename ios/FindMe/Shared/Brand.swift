import SwiftUI

// MARK: - Find Me! brand: logo + loading
//
// Logo = ghim bản đồ (pin) có dấu "!" đặt giữa vòng la bàn, nối với icon app.
// Loading = "radar săn kho báu": ghim nhảy trên dấu X, sóng dò lan trên mặt đất,
// tia quét radar và la bàn quay chậm trên nền giấy bản đồ. Tôn trọng Reduce Motion.
// Tất cả màu lấy từ token trong Theme.swift nên tự đổi theo sáng/tối.

// MARK: Shapes

/// Ghim bản đồ: đầu tròn + mũi nhọn, nối bằng hai tiếp tuyến.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / 2, rect.height * 0.36)
        let c = CGPoint(x: rect.midX, y: rect.minY + r)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let a = acos(r / (tip.y - c.y))  // góc giữa trục thẳng đứng và bán kính tới tiếp điểm
        let right = CGPoint(x: c.x + r * sin(a), y: c.y + r * cos(a))
        let left = CGPoint(x: c.x - r * sin(a), y: c.y + r * cos(a))
        var cone = Path()
        cone.addLines([tip, right, left])
        cone.closeSubpath()
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).union(cone)
    }
}

/// Ghim thương hiệu: thân accent có ánh sáng, đĩa giấy bên trong, dấu "!" vẽ bằng shape.
struct FMPin: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let r = min(w / 2, geo.size.height * 0.36)
            let disc = r * 1.22
            ZStack(alignment: .top) {
                PinShape()
                    .fill(Color.fmAccent)
                    .overlay {
                        // Ánh sáng góc trên trái cho cảm giác khối.
                        PinShape().fill(
                            RadialGradient(colors: [.white.opacity(0.35), .clear],
                                           center: UnitPoint(x: 0.3, y: 0.18), startRadius: 0, endRadius: w * 0.7))
                    }
                    .shadow(color: Color.fmAccent.opacity(0.35), radius: w * 0.08, y: w * 0.06)
                Circle()
                    .fill(Color.fmSurface)
                    .frame(width: disc, height: disc)
                    .offset(y: r - disc / 2)
                VStack(spacing: disc * 0.07) {
                    Capsule().frame(width: disc * 0.16, height: disc * 0.42)
                    Circle().frame(width: disc * 0.17, height: disc * 0.17)
                }
                .foregroundStyle(Color.fmAccent)
                .offset(y: r - disc * 0.36)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Vòng la bàn: 60 vạch (vạch chính ở 4 hướng) + mũi tên Bắc.
struct CompassRing: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = min(size.width, size.height) / 2
            for i in 0..<60 {
                let ang = Double(i) / 60 * 2 * .pi - .pi / 2
                let major = i % 15 == 0
                let len = major ? R * 0.11 : (i % 5 == 0 ? R * 0.065 : R * 0.035)
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(ang) * R, y: c.y + sin(ang) * R))
                tick.addLine(to: CGPoint(x: c.x + cos(ang) * (R - len), y: c.y + sin(ang) * (R - len)))
                ctx.stroke(tick, with: .color(Color.fmAccent.opacity(major ? 0.9 : 0.35)),
                           style: StrokeStyle(lineWidth: major ? max(1.5, R * 0.025) : 1, lineCap: .round))
            }
            let s = R * 0.09
            var north = Path()
            north.move(to: CGPoint(x: c.x, y: c.y - R - s * 0.2))
            north.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y - R + s * 1.3))
            north.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - R + s * 1.3))
            north.closeSubpath()
            ctx.fill(north, with: .color(Color.fmDanger))
        }
    }
}

// MARK: Logo

/// Biểu tượng tĩnh: ghim trong vòng la bàn trên nền giấy.
struct FMLogoMark: View {
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle().fill(Color.fmAccentSoft)
            Circle()
                .strokeBorder(Color.fmAccent.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
                .padding(size * 0.17)
            CompassRing().padding(size * 0.05)
            GroundX(size: size * 0.16).offset(y: size * 0.22).opacity(0.55)
            FMPin()
                .frame(width: size * 0.34, height: size * 0.44)  // mũi ghim chạm đúng dấu X
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Chữ "Find Me!" serif, dấu "!" màu accent hơi nghiêng như vừa reo lên.
struct FMWordmark: View {
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -size * 0.04) {
            Text(verbatim: "Find Me").foregroundStyle(Color.fmText)
            Text(verbatim: "!")
                .foregroundStyle(Color.fmAccent)
                .rotationEffect(.degrees(10), anchor: .bottom)
        }
        .font(.system(size: size, weight: .black, design: .serif))
        .kerning(-size * 0.01)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Find Me!"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Dấu X kho báu vẽ trên mặt đất.
private struct GroundX: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Capsule().frame(width: size, height: size * 0.2).rotationEffect(.degrees(45))
            Capsule().frame(width: size, height: size * 0.2).rotationEffect(.degrees(-45))
        }
        .foregroundStyle(Color.fmAccent)
        .scaleEffect(y: 0.45)  // nằm phẳng theo phối cảnh
    }
}

// MARK: Loading

/// Khung cảnh động, điều khiển hoàn toàn bằng thời gian `t` (giây) nên không bao giờ giật state.
struct HuntScene: View {
    let t: Double
    var size: CGFloat = 220

    var body: some View {
        let hopPeriod = 1.3
        let h = abs(sin(.pi * t / hopPeriod))            // 0 = chạm đất, 1 = đỉnh
        let squash = pow(1 - h, 8) * 0.14                // bẹp khi tiếp đất
        let pinW = size * 0.27, pinH = pinW * 1.32
        let groundY = size * 0.66
        let center = CGPoint(x: size / 2, y: size / 2)

        ZStack {
            Circle().fill(Color.fmAccentSoft.opacity(0.55))
                .frame(width: size * 0.9, height: size * 0.9)

            // Tia quét radar.
            Circle()
                .fill(AngularGradient(stops: [
                    .init(color: Color.fmAccent.opacity(0), location: 0),
                    .init(color: Color.fmAccent.opacity(0), location: 0.72),
                    .init(color: Color.fmAccent.opacity(0.22), location: 0.995),
                    .init(color: Color.fmAccent.opacity(0), location: 1),
                ], center: .center))
                .frame(width: size * 0.9, height: size * 0.9)
                .rotationEffect(.degrees(t * 110))

            Circle()
                .strokeBorder(Color.fmAccent.opacity(0.3),
                              style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 6], dashPhase: -t * 14))
                .frame(width: size * 0.62, height: size * 0.62)

            CompassRing()
                .frame(width: size * 0.96, height: size * 0.96)
                .rotationEffect(.degrees(sin(t * 0.7) * 18))   // kim la bàn dao động như đang dò hướng

            // Sóng dò lan trên mặt đất.
            ForEach(0..<3, id: \.self) { i in
                let p = (t / 2.1 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let w = size * (0.14 + p * 0.6)
                Ellipse()
                    .stroke(Color.fmAccent.opacity((1 - p) * 0.55), lineWidth: 1.5)
                    .frame(width: w, height: w * 0.32)
                    .position(x: center.x, y: groundY)
            }

            GroundX(size: size * 0.11).opacity(0.5).position(x: center.x, y: groundY)

            Ellipse()
                .fill(Color.fmText.opacity(0.2 - 0.12 * h))
                .frame(width: pinW * (0.95 - 0.45 * h), height: pinW * 0.22 * (1 - 0.4 * h))
                .position(x: center.x, y: groundY)

            ForEach(0..<3, id: \.self) { i in
                let phase = sin(2 * .pi * (t / 1.8 + Double(i) / 3))
                let o = max(0, phase)
                let ang = [-0.55, -0.15, 0.3][i] * .pi - .pi / 2
                Image(systemName: "sparkle")
                    .font(.system(size: size * [0.07, 0.05, 0.06][i], weight: .bold))
                    .foregroundStyle(Color.fmTreasure)
                    .scaleEffect(0.4 + 0.6 * o)
                    .opacity(o)
                    .position(x: center.x + cos(ang) * size * 0.27, y: center.y - size * 0.06 + sin(ang) * size * 0.25)
            }

            FMPin()
                .frame(width: pinW, height: pinH)
                .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                .rotationEffect(.degrees(sin(.pi * t / hopPeriod) * 5), anchor: .bottom)
                .offset(y: -h * size * 0.13)
                .position(x: center.x, y: groundY - pinH / 2)
        }
        .frame(width: size, height: size)
    }
}

/// Nền giấy bản đồ: lưới chấm và một đường mòn chấm chấm dẫn tới dấu X.
struct MapBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                             with: .color(Color.fmBorder.opacity(0.7)))
                    x += step
                }
                y += step
            }
            let w = size.width, h = size.height
            var trail = Path()
            trail.move(to: CGPoint(x: -10, y: h * 0.88))
            trail.addCurve(to: CGPoint(x: w * 0.55, y: h * 0.78),
                           control1: CGPoint(x: w * 0.2, y: h * 0.7), control2: CGPoint(x: w * 0.35, y: h * 0.95))
            trail.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.16),
                           control1: CGPoint(x: w * 0.85, y: h * 0.6), control2: CGPoint(x: w * 0.6, y: h * 0.3))
            ctx.stroke(trail, with: .color(Color.fmBorder),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 9]))
            let xc = CGPoint(x: w * 0.82, y: h * 0.16), s: CGFloat = 9
            var mark = Path()
            mark.move(to: CGPoint(x: xc.x - s, y: xc.y - s)); mark.addLine(to: CGPoint(x: xc.x + s, y: xc.y + s))
            mark.move(to: CGPoint(x: xc.x + s, y: xc.y - s)); mark.addLine(to: CGPoint(x: xc.x - s, y: xc.y + s))
            ctx.stroke(mark, with: .color(Color.fmAccent.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .background(Color.fmCanvas)
        .accessibilityHidden(true)
    }
}

/// Màn hình chờ toàn màn hình. Không truyền `message` thì chú thích tự đổi theo hành trình.
struct FMLoadingView: View {
    var message: LocalizedStringResource?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var captionIndex = 0

    private static var captions: [LocalizedStringResource] {
        ["Đang mở bản đồ kho báu…", "Đang lần theo dấu chân…", "Đang soi từng góc phố…", "Sắp tìm thấy rồi!"]
    }

    var body: some View {
        VStack(spacing: 28) {
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? 0.45 : ctx.date.timeIntervalSince(start)
                VStack(spacing: 28) {
                    HuntScene(t: t, size: 232)
                    FMWordmark(size: 30)
                    StepDots(t: t)
                }
            }
            ZStack {
                Text(message ?? Self.captions[captionIndex % Self.captions.count])
                    .font(.fmHeadline)
                    .foregroundStyle(Color.fmTextSecondary)
                    .multilineTextAlignment(.center)
                    .id(captionIndex)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
            .frame(height: 44)
            .clipped()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { MapBackdrop().ignoresSafeArea() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Đang tải"))
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: message == nil) {
            guard message == nil, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(duration: 0.5)) { captionIndex += 1 }
            }
        }
    }
}

/// Ba "bước chân" sáng lần lượt dưới logo.
private struct StepDots: View {
    let t: Double
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                let o = max(0, sin(2 * .pi * (t / 1.3 - Double(i) / 6)))
                Capsule()
                    .fill(Color.fmAccent.opacity(0.25 + 0.75 * o))
                    .frame(width: 8 + 10 * o, height: 8)
            }
        }
        .frame(width: 70)
    }
}

/// Lớp phủ khi đang xử lý trên một màn hình có sẵn (đăng nhập, gửi…).
struct FMLoadingOverlay: View {
    var message: LocalizedStringResource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        ZStack {
            Color.fmCanvas.opacity(0.55).ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.6))
            VStack(spacing: 10) {
                TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { ctx in
                    HuntScene(t: reduceMotion ? 0.45 : ctx.date.timeIntervalSince(start), size: 120)
                }
                Text(message)
                    .font(.fmHeadline)
                    .foregroundStyle(Color.fmText)
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 22)
            .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
            .shadow(color: Color.fmText.opacity(0.12), radius: 24, y: 10)
            .accessibilityElement(children: .combine)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

#Preview("Loading") { FMLoadingView() }
#Preview("Logo") {
    VStack(spacing: 16) {
        FMLogoMark()
        FMWordmark()
        TreasureDivider().frame(width: 160)
    }
    .padding()
    .background(Color.fmCanvas)
}
#Preview("Overlay") { FMLoadingOverlay(message: "Đang đăng nhập…") }

// MARK: - Lấp lánh

extension View {
    /// Hiệu ứng "kho báu" cho thẻ cần nổi bật (vd. "Game của tôi"):
    /// - viền sáng màu `tint` chạy vòng quanh thẻ,
    /// - vài ngôi sao nhỏ nhấp nháy lệch nhịp ở mép thẻ.
    /// Không chặn chạm; khi bật Reduce Motion chỉ còn viền tĩnh.
    func fmShimmer(tint: Color = .fmTreasure, cornerRadius: CGFloat = FM.radiusLarge) -> some View {
        modifier(FMShimmer(tint: tint, cornerRadius: cornerRadius))
    }
}

private struct FMShimmer: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    /// Vị trí (tỉ lệ theo thẻ), cỡ và độ lệch nhịp của từng ngôi sao: nằm sát mép để không che chữ.
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.60, 0.14, 11, 0.0), (0.93, 0.78, 9, 1.1), (0.30, 0.88, 7, 2.0), (0.80, 0.10, 6, 2.7),
    ]

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                if !reduceMotion {
                    ZStack {
                        GeometryReader { geo in
                            ForEach(Self.stars.indices, id: \.self) { i in
                                let s = Self.stars[i]
                                Twinkle(size: s.size, delay: s.delay, tint: tint)
                                    .position(x: geo.size.width * s.x, y: geo.size.height * s.y)
                            }
                        }
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                // Viền: nền mảnh màu tint + một đoạn sáng chạy vòng quanh.
                ZStack {
                    shape.strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    // Xoay cả lớp gradient (vuông, đủ phủ góc thẻ) rồi cắt theo viền: mượt hơn
                    // animate góc của AngularGradient.
                    GeometryReader { geo in
                        let side = max(geo.size.width, geo.size.height) * 1.5
                        AngularGradient(stops: [
                            .init(color: tint.opacity(0), location: 0),
                            .init(color: tint.opacity(0), location: 0.6),
                            .init(color: tint, location: 0.8),
                            .init(color: .white.opacity(0.95), location: 0.84),
                            .init(color: tint, location: 0.88),
                            .init(color: tint.opacity(0), location: 1),
                        ], center: .center)
                            .frame(width: side, height: side)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .mask(shape.strokeBorder(lineWidth: 2))
                        .opacity(reduceMotion ? 0 : 1)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: tint.opacity(0.22), radius: 12, y: 5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { spin = true }
            }
    }

}

/// Ngôi sao 4 cánh: phóng to + xoay nhẹ rồi tắt, lặp lại lệch nhịp theo `delay`.
private struct Twinkle: View {
    let size: CGFloat
    let delay: Double
    let tint: Color
    @State private var on = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [.white, tint], startPoint: .top, endPoint: .bottom))
            .shadow(color: tint.opacity(0.8), radius: 3)
            .scaleEffect(on ? 1 : 0.1)
            .rotationEffect(.degrees(on ? 45 : 0))
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) {
                    on = true
                }
            }
    }
}
