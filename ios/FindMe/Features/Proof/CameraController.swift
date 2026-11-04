@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// In-app capture only (F-18, N-04): AVFoundation still photo, no photo-library access.
final class CameraController: NSObject, @unchecked Sendable {
    enum SetupResult: Sendable { case ready, denied, unavailable }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "findme.camera")
    private var configured = false
    private var pending: CheckedContinuation<Data, Error>?

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() async -> SetupResult {
        guard await Self.authorize() else { return .denied }
        return await withCheckedContinuation { cont in
            queue.async { [self] in
                if !configured {
                    guard configure() else { cont.resume(returning: .unavailable); return }
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                cont.resume(returning: .ready)
            }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        return true
    }

    /// Returns the captured photo's file data (later re-encoded, which strips EXIF).
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                pending = cont
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                if let connection = output.connection(with: .video) {
                    let angle: CGFloat = 90  // portrait UI
                    if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                }
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let cont = pending
        pending = nil
        if let error { cont?.resume(throwing: error); return }
        if let data = photo.fileDataRepresentation() { cont?.resume(returning: data) }
        else { cont?.resume(throwing: CocoaError(.fileReadCorruptFile)) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
