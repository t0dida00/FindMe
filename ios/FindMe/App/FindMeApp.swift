import SwiftUI
import Supabase

@main
struct FindMeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthStore()
    @State private var router = AppRouter.shared

    init() {
        Theme.applyAppearance()
        KeyboardDismissal.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.fmAccent)
                .foregroundStyle(.fmText)
                .background(Color.fmCanvas.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .environment(auth)
                .environment(router)
                .task { await auth.start() }
                .onOpenURL { url in
                    if url.host == "login-callback" {
                        Supa.client.auth.handle(url)
                    } else {
                        router.handle(url: url)
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            if DesignPreview.enabled {
                MainTabView()
            } else if !AppConfig.isConfigured {
                ConfigMissingView()
            } else {
                switch auth.state {
                case .loading:
                    FMLoadingView()
                case .signedOut:
                    SignInView()
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(.default, value: auth.state)
    }
}

struct ConfigMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Chưa cấu hình Supabase", systemImage: "gearshape.2")
        } description: {
            Text("Tạo file ios/Config/Secrets.xcconfig với SUPABASE_URL và SUPABASE_ANON_KEY rồi build lại. Xem ios/README.md.")
        }
    }
}

/// Chỉ dùng khi debug: chạy app với `-FMDesignPreview` để xem giao diện chính mà không cần đăng nhập.
enum DesignPreview {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-FMDesignPreview")
        #else
        false
        #endif
    }
}
