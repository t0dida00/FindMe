import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEmail = false

    var body: some View {
        @Bindable var auth = auth
        VStack(spacing: 16) {
            Spacer()
            FMLogoMark(size: 148)
            FMWordmark(size: 46)
            TreasureDivider().frame(width: 160)
            Text("Săn kho báu trực tiếp cùng bạn bè. Giải hint, tìm tờ giấy mã, nhập mã và chụp ảnh để thắng.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.fmTextSecondary)
                .padding(.horizontal)
            Spacer()

            if !AppConfig.isFreeTeam {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
            }

            Button {
                Task { await auth.signInWithGoogle() }
            } label: {
                Label("Đăng nhập với Google", systemImage: "globe")
            }
            .buttonStyle(.fmPrimary)

            Button { showEmail = true } label: {
                Label("Đăng nhập bằng email", systemImage: "envelope")
            }
            .buttonStyle(.fmSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fmCanvas.ignoresSafeArea())
        .disabled(auth.isWorking)
        .overlay { if auth.isWorking { FMLoadingOverlay(message: "Đang đăng nhập…") } }
        .animation(.smooth(duration: 0.25), value: auth.isWorking)
        .sheet(isPresented: $showEmail) { EmailOTPSheet() }
        .errorAlert($auth.errorMessage)
    }
}

private struct EmailOTPSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(sent ? "Gửi lại mã" : "Gửi mã đăng nhập") {
                        Task { sent = await auth.sendOTP(email: email.trimmingCharacters(in: .whitespaces)) }
                    }
                    .disabled(!email.contains("@") || auth.isWorking)
                } footer: {
                    Text("Dành cho môi trường phát triển. Mã được gửi qua email.")
                }
                if sent {
                    Section {
                        Text("Mở email trên iPhone này và bấm link \"Sign in\" để vào app.")
                    }
                    Section("Hoặc nhập mã (nếu email có mã)") {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("Xác nhận") {
                            Task {
                                await auth.verifyOTP(email: email.trimmingCharacters(in: .whitespaces), code: code)
                                if auth.userId != nil { dismiss() }
                            }
                        }
                        .disabled(code.count < 6 || auth.isWorking)
                    }
                }
            } }.fmScreen()
            .navigationTitle("Đăng nhập bằng email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        }
    }
}
