import Foundation

struct RemoteSessionDiscovery: Sendable {
    let backends: [any RemoteSessionBackend]

    init(backends: [any RemoteSessionBackend] = RemoteSessionBackends.all) {
        self.backends = backends
    }

    func discover(using runner: any RemoteCommandRunning) async -> [RemoteSessionEntry] {
        []
    }
}
