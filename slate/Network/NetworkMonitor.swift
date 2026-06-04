import Network
import Foundation

@Observable
final class NetworkMonitor {
    private(set) var isConnected = false
    var onConnectionRestored: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "slate.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected
                if connected && !wasConnected {
                    self.onConnectionRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
