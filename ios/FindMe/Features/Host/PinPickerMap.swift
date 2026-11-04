import MapKit
import SwiftUI

/// Host picks a location (hint answer, or the game's public area on the Globe): tap anywhere to move
/// the pin, or drag the pin (MapReader + MapProxy, iOS 17).
struct PinPickerMap: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    private let emptyPrompt: LocalizedStringKey
    private let movePrompt: LocalizedStringKey
    private let pinLabel: LocalizedStringKey
    /// Khóa: chỉ xem, không chạm/kéo ghim, không kéo/phóng bản đồ (hint đang chơi hoặc đã giải).
    private let locked: Bool
    /// A request from outside to move the camera (e.g. an address was found); taps don't move it.
    /// Each request has its own id, so asking for the same place twice still moves the camera.
    struct CameraTarget: Equatable {
        var coordinate: CLLocationCoordinate2D
        var id = UUID()
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }
    private let cameraTarget: CameraTarget?
    private let meters: CLLocationDistance
    @State private var position: MapCameraPosition
    @State private var dragOffset: CGSize = .zero

    /// Default camera: Ho Chi Minh City.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)

    init(coordinate: Binding<CLLocationCoordinate2D?>,
         meters: CLLocationDistance = 1500,
         emptyPrompt: LocalizedStringKey = "Chạm để đặt ghim đáp án",
         movePrompt: LocalizedStringKey = "Chạm hoặc kéo ghim để đổi vị trí",
         pinLabel: LocalizedStringKey = "Ghim đáp án",
         locked: Bool = false,
         cameraTarget: CameraTarget? = nil) {
        _coordinate = coordinate
        self.locked = locked
        self.cameraTarget = cameraTarget
        self.meters = meters
        self.emptyPrompt = emptyPrompt
        self.movePrompt = movePrompt
        self.pinLabel = pinLabel
        let center = coordinate.wrappedValue ?? Self.defaultCenter
        _position = State(initialValue: .region(MKCoordinateRegion(center: center, latitudinalMeters: meters,
                                                                    longitudinalMeters: meters)))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: locked ? [] : .all) {
                if let coordinate {
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white, .fmDanger)
                            .shadow(radius: 3)
                            .offset(dragOffset)
                            .gesture(locked ? nil :
                                DragGesture(coordinateSpace: .named("pinmap"))
                                    .onChanged { dragOffset = $0.translation }
                                    .onEnded { value in
                                        dragOffset = .zero
                                        if let c = proxy.convert(value.location, from: .named("pinmap")) { self.coordinate = c }
                                    }
                            )
                            .accessibilityLabel(Text(pinLabel))
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .coordinateSpace(.named("pinmap"))
            .onTapGesture(coordinateSpace: .named("pinmap")) { point in
                guard !locked else { return }
                if let c = proxy.convert(point, from: .named("pinmap")) { coordinate = c }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: cameraTarget) { _, target in
            guard let c = target?.coordinate else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Group {
                if locked {
                    Label("Vị trí đã khóa", systemImage: "lock.fill")
                } else {
                    Text(coordinate == nil ? emptyPrompt : movePrompt)
                }
            }
                .font(.caption.weight(.semibold))
                .padding(6).background(.thinMaterial, in: Capsule()).padding(8)
        }
    }
}
