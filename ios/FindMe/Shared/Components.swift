import SwiftUI

extension View {
    /// Shows an alert whenever the bound message is non-nil.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Có lỗi xảy ra", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// Live countdown "mm:ss" until a date (updates every second, VoiceOver friendly).
struct CountdownText: View {
    let until: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
            Text(Self.format(remaining))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct StatusChip: View {
    let text: LocalizedStringKey
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

extension GameStatus {
    var label: LocalizedStringKey {
        switch self {
        case .draft: "Bản nháp"
        case .scheduled: "Đã hẹn giờ"
        case .live: "Đang diễn ra"
        case .completed: "Đã kết thúc"
        case .cancelled: "Đã hủy"
        }
    }
    /// Nhãn ngắn cho chip ở thẻ hẹp (vd. "Game của tôi"), để tên game không bị đẩy xuống dòng.
    var shortLabel: LocalizedStringKey {
        self == .live ? "Live" : label
    }
    var color: Color {
        switch self {
        case .draft: .fmMuted
        case .scheduled: .fmInfo
        case .live: .fmTreasure
        case .completed: .fmAccent
        case .cancelled: .fmDanger
        }
    }
}

extension ParticipantRole {
    var label: LocalizedStringKey {
        switch self {
        case .host: "Quản trò"
        case .cohost: "Co-host"
        case .player: "Người chơi"
        }
    }
}

extension SubmissionStatus {
    var label: LocalizedStringKey {
        switch self {
        case .reserved: "Đang chờ ảnh"
        case .pending: "Đang chờ duyệt"
        case .approved: "Được duyệt"
        case .denied: "Bị từ chối"
        case .expired: "Hết hạn"
        }
    }
    var color: Color {
        switch self {
        case .reserved: .fmAccent
        case .pending: .fmInfo
        case .approved: .fmSuccess
        case .denied: .fmDanger
        case .expired: .fmMuted
        }
    }
}

/// Image from a private bucket via signed URL.
struct SignedImage: View {
    let bucket: String
    let path: String
    var contentMode: ContentMode = .fit
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure: placeholder(systemImage: "exclamationmark.triangle")
                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
            } else if failed {
                placeholder(systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: path) {
            do { url = try await SignedURLCache.shared.url(bucket: bucket, path: path) } catch { failed = true }
        }
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.largeTitle).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Color.fmSunken, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(Text("Không tải được ảnh"))
    }
}

/// Top banner ("[Tên] đã tìm ra Hint X", F-26).
struct BannerView: View {
    let text: String
    /// true: "Đã lưu…" (dấu tích xanh) thay cho cờ sự kiện.
    var success = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "flag.checkered")
                .font(.title3).foregroundStyle(success ? Color.fmSuccess : Color.fmAccent)
            Text(text).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.fmText)
        .fmCard()
        .shadow(color: Color.fmText.opacity(0.12), radius: 12, y: 6)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Round avatar from the public `avatars` bucket, falling back to initials on a tinted circle.
struct AvatarView: View {
    let path: String?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            initials
            if let path, let url = API.avatarURL(path: path) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Circle()
            .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(Self.initials(of: name))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// Stable colour per name, so the same person always gets the same circle.
    private var tint: Color {
        let palette: [Color] = [.fmAccent, .pink, .fmAccent, .fmAccent, .fmInfo, .teal, .fmSuccess, .mint]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return palette[hash % palette.count]
    }

    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = words.count >= 2 ? [words.first!, words.last!].compactMap(\.first) : words.first.map { Array($0.prefix(1)) } ?? []
        let s = String(letters).uppercased()
        return s.isEmpty ? "?" : s
    }
}

// MARK: - Từ khóa / con số nhấn mạnh

/// Dòng thông tin có phần nhấn mạnh: GIÁ TRỊ (tên quản trò, mã, ngày giờ) và con số (số người chơi,
/// số hint) dùng fontWeight 700 + màu chữ chính (sáng); nhãn ("Quản trò:", "Mã:") giữ kiểu của ngữ
/// cảnh (thường là chữ phụ). Dựng bằng AttributedString nên một Text duy nhất, xuống dòng tự nhiên.
enum Emphasis {
    /// "Quản trò: **Minh Thư**"
    static func keyword(_ key: LocalizedStringResource, _ value: String) -> Text {
        Text(AttributedString(localized: key) + AttributedString(" ") + strong(AttributedString(value)))
    }

    /// "**5** người chơi · **3** hint"
    static func counts(_ parts: [(Int, LocalizedStringResource)]) -> Text {
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { out += AttributedString(" · ") }
            out += strong(AttributedString(part.0.formatted()))
            out += AttributedString(" ") + AttributedString(localized: part.1)
        }
        return Text(out)
    }

    private static func strong(_ s: AttributedString) -> AttributedString {
        var s = s
        s.inlinePresentationIntent = .stronglyEmphasized   // bold = weight 700
        s.foregroundColor = Color.fmText
        return s
    }
}
