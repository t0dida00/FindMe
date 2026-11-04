import CoreLocation
import MapKit
import SwiftUI

/// F-21: pins of solved hints (position set by the host) joined into a journey polyline.
/// Staff also see every hint that isn't solved yet (current + upcoming), from `hints` which only
/// staff can read; players never get those coordinates.
/// The player's own location is shown on-device only (MapKit user location), never sent to the server (N-10).
struct JourneyMapView: View {
    @Environment(GameViewModel.self) private var vm
    @State private var location = LocationPermission()
    @State private var selected: Int?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        let answers = vm.revealedAnswers
        let solvedOrders = Set(answers.map(\.hintOrder))
        let pending = vm.isStaff
            ? vm.hostHints.filter { !solvedOrders.contains($0.hintOrder) }.sorted { $0.hintOrder < $1.hintOrder }
            : []
        let allStaffHints = vm.hostHints.sorted { $0.hintOrder < $1.hintOrder }
        Map(position: $position, selection: $selected) {
            // Staff: cả lộ trình dự kiến (mờ), lộ trình đã đi (đậm) vẽ đè lên trên.
            if vm.isStaff && allStaffHints.count > 1 {
                MapPolyline(coordinates: allStaffHints.map(\.coordinate))
                    .stroke(Color.fmMuted, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6]))
            }
            if answers.count > 1 {
                MapPolyline(coordinates: answers.map(\.coordinate))
                    .stroke(.fmAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
            }
            ForEach(answers) { a in
                Marker(a.hintTitle ?? String(localized: "Hint \(a.hintOrder)"),
                       monogram: Text("\(a.hintOrder)"), coordinate: a.coordinate)
                    .tint(.fmAccent)
                    .tag(a.hintOrder)
            }
            ForEach(pending) { h in
                Marker(h.title ?? String(localized: "Hint \(h.hintOrder)"),
                       monogram: Text("\(h.hintOrder)"), coordinate: h.coordinate)
                    .tint(isCurrent(h) ? Color.fmWarning : Color.fmMuted)
            }
            if location.authorized { UserAnnotation() }
        }
        .mapControls {
            if location.authorized { MapUserLocationButton() }
            MapCompass()
            MapScaleView()
        }
        .overlay {
            if vm.isStaff {
                if vm.hostHints.isEmpty {
                    ContentUnavailableView("Chưa có hint nào", systemImage: "mappin.slash",
                                           description: Text("Thêm hint ở tab Quản lý để thấy ghim ở đây."))
                        .background(.ultraThinMaterial)
                }
            } else if answers.isEmpty {
                ContentUnavailableView("Chưa có hint nào được giải", systemImage: "mappin.slash",
                                       description: Text("Ghim đáp án sẽ hiện ở đây sau khi mỗi hint được tìm ra."))
                    .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            if vm.isStaff && !vm.hostHints.isEmpty { legend.padding(.bottom, 8) }
        }
        .onAppear { location.requestIfNeeded() }
        .sheet(item: Binding(get: { answers.first { $0.hintOrder == selected } },
                             set: { if $0 == nil { selected = nil } })) { answer in
            AnswerDetailSheet(answer: answer).presentationDetents([.medium, .large])
        }
    }

    private func isCurrent(_ h: HostHint) -> Bool {
        vm.game?.status == .live && vm.game?.currentHintOrder == h.hintOrder
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Đã giải", color: .fmAccent)
            legendItem("Đang mở", color: .fmWarning)
            legendItem("Chưa mở", color: .fmMuted)
        }
        .font(.caption).foregroundStyle(Color.fmText)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private func legendItem(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

extension HostHint {
    var coordinate: CLLocationCoordinate2D { .init(latitude: answerLat, longitude: answerLng) }
}

extension RevealedAnswer {
    var coordinate: CLLocationCoordinate2D { .init(latitude: answerLat, longitude: answerLng) }
}

struct AnswerDetailSheet: View {
    let answer: RevealedAnswer
    var body: some View {
        NavigationStack {
            List { ThemedRows {
                Section {
                    LabeledContent("Người tìm ra") { Text(verbatim: answer.winnerName).bold().foregroundStyle(Color.fmText) }
                    LabeledContent("Lúc", value: Fmt.dateTime(answer.solvedAt))
                    if let s = answer.secondsToSolve { LabeledContent("Thời gian tìm", value: Fmt.duration(seconds: s)) }
                }
                if let path = answer.winnerPhotoPath {
                    Section("Ảnh mã") {
                        SignedImage(bucket: "proofs", path: path)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } }.fmScreen()
            .navigationTitle(answer.hintTitle ?? String(localized: "Hint \(answer.hintOrder)"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Requests when-in-use permission lazily (only when the map opens).
@MainActor @Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorized = false

    override init() {
        super.init()
        manager.delegate = self
        authorized = Self.isAuthorized(manager.authorizationStatus)
    }

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorized = Self.isAuthorized(status) }
    }

    nonisolated static func isAuthorized(_ s: CLAuthorizationStatus) -> Bool {
        s == .authorizedWhenInUse || s == .authorizedAlways
    }
}
