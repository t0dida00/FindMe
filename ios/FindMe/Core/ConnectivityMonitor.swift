import Foundation
import Network
import Observation

/// N-12: notices when the network comes back so screens can resync.
@MainActor @Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()
    private(set) var isOnline = true
    /// Increments each time connectivity is regained.
    private(set) var reconnectTick = 0
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "findme.connectivity"))
    }

    private func update(_ online: Bool) {
        if online && !isOnline { reconnectTick += 1 }
        isOnline = online
    }
}
