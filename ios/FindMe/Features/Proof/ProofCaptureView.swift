import Observation
import SwiftUI
import UIKit

/// Opens right after a correct code: camera + visible countdown to upload_deadline, then compress →
/// upload to the slot the server picks in proofs/<game>/<me>/ (retrying until the deadline) → attach.
@MainActor @Observable
final class ProofCaptureModel {
    enum Phase: Equatable {
        case camera
        case uploading(attempt: Int)
        case attaching
        case done
        case expired
        case failed(String)
    }

    let target: ProofTarget
    private(set) var phase: Phase = .camera
    private(set) var preview: UIImage?
    let camera = CameraController()
    var cameraState: CameraController.SetupResult?
    private var jpeg: Data?
    /// Asked once and reused by every retry, so a retry after a lost response is idempotent.
    private var slot: API.UploadSlot?

    init(target: ProofTarget) {
        self.target = target
    }

    var isPastDeadline: Bool { Date() >= target.deadline }

    func startCamera() async {
        cameraState = await camera.start()
    }

    func capture() async {
        do {
            let data = try await camera.capture()
            guard let image = UIImage(data: data) else { throw API.APIError.compressionFailed }
            await process(image)
        } catch {
            phase = .failed(AppError.message(for: error))
        }
    }

    /// Simulator has no camera: lets developers exercise the flow with a generated image.
    func useSimulatorTestImage() async {
        let size = CGSize(width: 1200, height: 1600)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemYellow.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let text = "TEST PROOF \(Date().formatted(date: .omitted, time: .standard))" as NSString
            text.draw(at: CGPoint(x: 80, y: 760), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72)])
        }
        await process(img)
    }

    private func process(_ image: UIImage) async {
        camera.stop()
        preview = image
        let compressed = await Task.detached(priority: .userInitiated) {
            ImageCompressor.jpeg(from: image)
        }.value
        guard let compressed else { phase = .failed(String(localized: "Không nén được ảnh.")); return }
        jpeg = compressed
        await uploadAndAttach()
    }

    /// N-09: retry the upload with backoff while the deadline has not passed.
    func uploadAndAttach() async {
        guard let jpeg else { return }
        var attempt = 0
        var lastError: Error?
        var uploaded = false
        while !uploaded && Date() < target.deadline {
            attempt += 1
            phase = .uploading(attempt: attempt)
            do {
                let slot: API.UploadSlot
                if let cached = self.slot {
                    slot = cached
                } else {
                    slot = try await API.newUpload(kind: "proof", gameId: gameIdFromPrefix)
                    self.slot = slot
                }
                try await withDeadline(target.deadline) {
                    try await API.upload(slot, data: jpeg)
                }
                uploaded = true
            } catch {
                lastError = error
                let backoff = min(4.0, 0.5 * Double(attempt))
                if Date().addingTimeInterval(backoff) >= target.deadline { break }
                try? await Task.sleep(for: .seconds(backoff))
            }
        }
        guard uploaded else {
            phase = Date() >= target.deadline ? .expired
                : .failed(lastError.map(AppError.message(for:)) ?? String(localized: "Tải ảnh thất bại."))
            return
        }
        guard let path = slot?.path else { return }
        phase = .attaching
        // attaching is tiny; retry a few times on transport errors (server re-checks the deadline).
        for i in 0..<4 {
            do {
                try await API.attachPhoto(submissionId: target.submissionId, path: path)
                let mine = try? await API.mySubmissions(gameId: gameIdFromPrefix)
                if mine?.first(where: { $0.id == target.submissionId })?.status == .expired {
                    phase = .expired
                } else {
                    phase = .done
                }
                return
            } catch let e as URLError {
                lastError = e
                try? await Task.sleep(for: .seconds(Double(i) + 0.5))
            } catch {
                phase = .failed(AppError.message(for: error))
                return
            }
        }
        phase = .failed(lastError.map(AppError.message(for:)) ?? String(localized: "Không gửi được mã."))
    }

    private var gameIdFromPrefix: UUID {
        UUID(uuidString: String(target.pathPrefix.split(separator: "/").first ?? "")) ?? UUID()
    }
}

/// Races `work` against a wall-clock deadline.
func withDeadline(_ deadline: Date, _ work: @escaping @Sendable () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await work() }
        group.addTask {
            let wait = max(0, deadline.timeIntervalSinceNow)
            try await Task.sleep(for: .seconds(wait))
            throw API.APIError.uploadDeadlinePassed
        }
        try await group.next()
        group.cancelAll()
    }
}

struct ProofCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProofCaptureModel
    let onFinish: () -> Void

    init(target: ProofTarget, onFinish: @escaping () -> Void) {
        _model = State(initialValue: ProofCaptureModel(target: target))
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                deadlineBar
                Spacer()
            }
        }
        .task {
            await model.startCamera()
        }
        .task {
            // Flip to "expired" if the window closes while still on the camera.
            let wait = max(0, model.target.deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(wait))
            if model.phase == .camera { model.camera.stop(); finishExpired() }
        }
        .onDisappear { model.camera.stop() }
        .interactiveDismissDisabled(isBusy)
        .preferredColorScheme(.dark)
    }

    @State private var expiredOnCamera = false
    private func finishExpired() { expiredOnCamera = true }

    private var isBusy: Bool {
        switch model.phase {
        case .uploading, .attaching: true
        default: false
        }
    }

    private var deadlineBar: some View {
        HStack {
            Image(systemName: "timer")
            Text("Còn lại")
            CountdownText(until: model.target.deadline).font(.title2.weight(.bold))
            Spacer()
            if !isBusy {
                Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                    .accessibilityLabel(Text("Đóng"))
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.5))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if expiredOnCamera {
            resultView(icon: "clock.badge.xmark", color: .fmWarning,
                       title: "Hết thời gian chụp ảnh",
                       message: "Mã đã được mở lại cho người khác. Bạn có thể nhập lại mã nếu chưa ai giữ.")
        } else {
            switch model.phase {
            case .camera:
                cameraView
            case .uploading(let attempt):
                progressView(title: attempt > 1 ? "Mạng yếu, đang thử lại (lần \(attempt))…" : "Đang tải ảnh lên…")
            case .attaching:
                progressView(title: "Đang gửi mã…")
            case .done:
                resultView(icon: "checkmark.seal.fill", color: .fmSuccess,
                           title: "Đã gửi mã!",
                           message: "Quản trò đang duyệt ảnh của bạn. Bạn sẽ được báo khi có kết quả.")
            case .expired:
                resultView(icon: "clock.badge.xmark", color: .fmWarning,
                           title: "Hết thời gian chụp ảnh",
                           message: "Ảnh đến muộn nên mã đã được mở lại cho người khác.")
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 56)).foregroundStyle(.fmDanger)
                    Text(message).multilineTextAlignment(.center).foregroundStyle(.white)
                    if !model.isPastDeadline, model.preview != nil {
                        Button("Thử lại") { Task { await model.uploadAndAttach() } }
                            .buttonStyle(.fmPrimaryCompact)
                    }
                    Button("Đóng") { close() }.foregroundStyle(.white)
                }
                .padding()
            }
        }
    }

    @ViewBuilder private var cameraView: some View {
        switch model.cameraState {
        case .ready:
            ZStack(alignment: .bottom) {
                CameraPreview(session: model.camera.session).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Chụp rõ tờ giấy có in mã")
                        .font(.subheadline.weight(.semibold))
                        .padding(8).background(.black.opacity(0.5), in: Capsule())
                    Button { Task { await model.capture() } } label: {
                        Circle().strokeBorder(.white, lineWidth: 5).frame(width: 78, height: 78)
                            .overlay(Circle().fill(.white).padding(9))
                    }
                    .accessibilityLabel(Text("Chụp ảnh"))
                }
                .foregroundStyle(.white)
                .padding(.bottom, 32)
            }
        case .denied:
            VStack(spacing: 16) {
                Text("Find Me! cần quyền camera để chụp ảnh mã. Hãy bật camera trong Cài đặt.")
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.fmPrimaryCompact)
            }
            .padding()
        case .unavailable:
            VStack(spacing: 16) {
                Text("Thiết bị này không có camera.").foregroundStyle(.white)
                #if targetEnvironment(simulator)
                Button("Dùng ảnh thử (Simulator)") { Task { await model.useSimulatorTestImage() } }
                    .buttonStyle(.fmPrimaryCompact)
                #endif
            }
        case nil:
            ProgressView().tint(.white)
        }
    }

    private func progressView(title: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            if let img = model.preview {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            ProgressView().tint(.white)
            Text(title).foregroundStyle(.white)
        }
        .padding()
    }

    private func resultView(icon: String, color: Color, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(color)
            Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
            Button("Xong") { close() }.buttonStyle(.fmPrimaryCompact)
        }
        .padding()
    }

    private func close() {
        model.camera.stop()
        onFinish()
        dismiss()
    }
}
