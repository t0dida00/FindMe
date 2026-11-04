import MapKit
import SwiftUI

/// Gợi ý địa điểm khi gõ (MKLocalSearchCompleter, chạy trên máy qua Apple Maps; không cần khóa API),
/// cùng các bước tìm tọa độ / tên khu vực mà AddressField dùng. Mọi kết quả trả ra đều Sendable.
@MainActor @Observable
final class PlaceSuggestions: NSObject, MKLocalSearchCompleterDelegate {
    struct Item: Identifiable, Hashable, Sendable {
        let title: String
        let subtitle: String
        var id: String { title + "\n" + subtitle }
    }

    struct Place: Sendable {
        let coordinate: CLLocationCoordinate2D
        /// Phường, quận, thành phố của chỗ đó (không có số nhà, tên đường hay tên quán).
        let areaName: String?
    }

    private(set) var items: [Item] = []
    /// Created on first use: @State re-runs this initializer whenever the parent view is rebuilt.
    @ObservationIgnored private var completer: MKLocalSearchCompleter?

    /// Gợi ý cho `text`, ưu tiên quanh `near` (ghim hiện tại) nếu có.
    func update(_ text: String, near: CLLocationCoordinate2D?) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { clear(); return }
        let c = completer ?? {
            let c = MKLocalSearchCompleter()
            c.delegate = self
            c.resultTypes = [.address, .pointOfInterest]
            completer = c
            return c
        }()
        if let near {
            c.region = MKCoordinateRegion(center: near, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        c.queryFragment = q
    }

    func clear() {
        completer?.cancel()
        items = []
    }

    // The completer calls its delegate on the main thread: update synchronously, so a clear()
    // that comes after can never be overwritten by results still queued.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            items = (self.completer?.results ?? []).prefix(5).map { Item(title: $0.title, subtitle: $0.subtitle) }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { items = [] }
    }

    // MARK: Lookups

    /// Tọa độ và tên khu vực của một gợi ý.
    static func place(of item: Item) async -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = item.subtitle.isEmpty ? item.title : "\(item.title), \(item.subtitle)"
        guard let mark = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark else { return nil }
        return Place(coordinate: mark.coordinate, areaName: areaName(mark))
    }

    /// Tọa độ của một địa chỉ gõ tay.
    static func coordinate(of address: String) async -> CLLocationCoordinate2D? {
        try? await CLGeocoder().geocodeAddressString(address).first?.location?.coordinate
    }

    /// Tên khu vực của một điểm (reverse geocode).
    static func areaName(at c: CLLocationCoordinate2D) async -> String? {
        let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        return mark.flatMap(areaName)
    }

    /// Phường · quận · thành phố (tối đa 80 ký tự, như cột area_name); ngoài vùng có tên thì tên nước.
    nonisolated static func areaName(_ m: CLPlacemark) -> String? {
        var parts: [String] = []
        for p in [m.subLocality, m.subAdministrativeArea ?? m.locality, m.administrativeArea] {
            if let p = p?.trimmingCharacters(in: .whitespaces), !p.isEmpty, !parts.contains(p) { parts.append(p) }
        }
        if parts.isEmpty, let country = m.country, !country.isEmpty { parts = [country] }
        let text = parts.joined(separator: ", ")
        return text.isEmpty ? nil : String(text.prefix(80))
    }
}

/// Danh sách gợi ý dưới ô địa chỉ. Nút `.borderless`: trong một hàng Form, nút thường bấm một cái
/// là kích hoạt cả hàng.
struct PlaceSuggestionList: View {
    let items: [PlaceSuggestions.Item]
    let onPick: (PlaceSuggestions.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                Button { onPick(item) } label: {
                    HStack(alignment: .top, spacing: FM.s) {
                        Image(systemName: "mappin.circle")
                            .foregroundStyle(Color.fmAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(Color.fmText)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.caption).foregroundStyle(Color.fmTextSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, FM.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                if item != items.last { Divider() }
            }
        }
    }
}
