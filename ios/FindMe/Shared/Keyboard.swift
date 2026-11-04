import SwiftUI
import UIKit

/// Cách thoát bàn phím, áp dụng cho mọi ô nhập trong app (kể cả trong sheet), không cần sửa từng màn:
/// - thanh "Xong" phía trên bàn phím (bàn phím số và ô nhiều dòng không có phím Return để thoát);
/// - chạm ra ngoài ô nhập để ẩn bàn phím (không chặn nút bấm);
/// - vuốt nội dung cuộn để ẩn bàn phím (`.scrollDismissesKeyboard` gắn ở `RootView`).
/// Gọi `KeyboardDismissal.install()` một lần lúc mở app.
@MainActor
enum KeyboardDismissal {
    private static var installed = false
    private static let tapDelegate = TapDelegate()

    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let view = note.object as? UIView
                MainActor.assumeIsolated { attachDoneBar(to: view) }
            }
        }
        center.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let window = note.object as? UIWindow
            MainActor.assumeIsolated { attachTap(to: window) }
        }
    }

    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: Thanh "Xong"

    private static func attachDoneBar(to view: UIView?) {
        let bar = makeDoneBar()
        if let field = view as? UITextField, field.inputAccessoryView == nil {
            field.inputAccessoryView = bar
            field.reloadInputViews()
        } else if let textView = view as? UITextView, textView.inputAccessoryView == nil, textView.isEditable {
            textView.inputAccessoryView = bar
            textView.reloadInputViews()
        }
    }

    private static func makeDoneBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.sizeToFit()
        let done = UIBarButtonItem(title: String(localized: "Xong"), primaryAction: UIAction { _ in dismiss() })
        done.style = .done
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.tintColor = UIColor(Color.fmAccent)
        return bar
    }

    // MARK: Chạm ra ngoài

    private static func attachTap(to window: UIWindow?) {
        guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === tapDelegate }) else { return }
        let tap = UITapGestureRecognizer(target: tapDelegate, action: #selector(TapDelegate.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = tapDelegate
        window.addGestureRecognizer(tap)
    }

    private final class TapDelegate: NSObject, UIGestureRecognizerDelegate {
        @objc func tapped() { KeyboardDismissal.dismiss() }

        /// Bỏ qua chạm vào chính ô nhập (để đổi ô hoặc đặt con trỏ) và thanh "Xong".
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView || v is UIToolbar { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
