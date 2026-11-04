import SwiftUI
import UIKit

// MARK: - Toast và nút sao chép
//
// | Thành phần    | Dùng cho                                                                   |
// |---------------|----------------------------------------------------------------------------|
// | FMToast       | thông báo ngắn ("Đã copy ID") nổi phía dưới, tự ẩn sau ~1,8 giây           |
// | FMCopyButton  | nút copy: chép vào clipboard, icon đổi sang dấu tích, rung nhẹ, hiện toast |
//
// Toast vẽ trong một UIWindow riêng (không nhận chạm) nên hiện cả trên sheet / full-screen cover.

@MainActor @Observable
final class FMToast {
    static let shared = FMToast()

    private(set) var message: String?
    private var hideTask: Task<Void, Never>?
    private var window: UIWindow?

    /// `text` đã dịch sẵn (`String(localized:)`).
    static func show(_ text: String) { shared.show(text) }

    private func show(_ text: String) {
        installWindowIfNeeded()
        withAnimation(.spring(duration: 0.3)) { message = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.message = nil }
        }
    }

    private func installWindowIfNeeded() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let host = UIHostingController(rootView: FMToastOverlay())
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.isUserInteractionEnabled = false
        w.isHidden = false
        window = w
    }
}

private struct FMToastOverlay: View {
    private let toast = FMToast.shared

    var body: some View {
        VStack {
            Spacer()
            if let message = toast.message {
                HStack(spacing: FM.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fmSuccess)
                    Text(verbatim: message).font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.fmCanvas)
                .padding(.horizontal, FM.m).padding(.vertical, FM.s + 2)
                .background(Color.fmText.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.bottom, FM.tabBarHeight + FM.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityHidden(true)  // đã đọc qua announcement
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }
}

/// Nút copy: icon `doc.on.doc` → dấu tích xanh ~1,5 giây, rung nhẹ, toast `toast`.
/// Kiểu nút (`.fmPill`, `.borderless`…) do chỗ dùng đặt.
struct FMCopyButton: View {
    let value: String
    /// Nội dung toast, ví dụ "Đã copy ID".
    let toast: LocalizedStringResource
    /// Nhãn VoiceOver trước khi copy.
    var accessibilityLabel: LocalizedStringKey = "Sao chép"
    var font: Font = .headline

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            ZStack {
                if copied {
                    Image(systemName: "checkmark").foregroundStyle(Color.fmSuccess)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "doc.on.doc")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .font(font.weight(.semibold))
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityLabel(copied ? Text("Đã sao chép") : Text(accessibilityLabel))
    }

    private func copy() {
        UIPasteboard.general.string = value
        withAnimation(.spring(duration: 0.25)) { copied = true }
        FMToast.show(String(localized: toast))
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}
