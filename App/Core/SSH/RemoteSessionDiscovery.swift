import Foundation

struct RemoteSessionDiscovery: Sendable {
    let backends: [any RemoteSessionBackend]

    init(backends: [any RemoteSessionBackend] = RemoteSessionBackends.all) {
        self.backends = backends
    }

    func discover(using runner: any RemoteCommandRunning) async -> [RemoteSessionEntry] {
        let results = await withTaskGroup(of: (Int, [RemoteSessionEntry]).self) { group in
            for (index, backend) in backends.enumerated() {
                group.addTask {
                    (index, await Self.entries(from: backend, using: runner))
                }
            }
            var collected: [Int: [RemoteSessionEntry]] = [:]
            for await (index, entries) in group {
                collected[index] = entries
            }
            return collected
        }
        return results.keys.sorted().flatMap { index in
            (results[index] ?? []).sorted(by: Self.nameOrder)
        }
    }

    private static func entries(from backend: any RemoteSessionBackend, using runner: any RemoteCommandRunning) async -> [RemoteSessionEntry] {
        guard let result = try? await runner.runCommand(backend.listCommand) else { return [] }
        let output = result.standardOutput
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return backend.parse(listOutput: output)
    }

    private static func nameOrder(_ lhs: RemoteSessionEntry, _ rhs: RemoteSessionEntry) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison == .orderedSame {
            return lhs.targetID < rhs.targetID
        }
        return comparison == .orderedAscending
    }
}
