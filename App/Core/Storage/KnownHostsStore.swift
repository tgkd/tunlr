import Foundation

actor KnownHostsStore {
    private let fileURL: URL
    private var hostKeys: [SSHHostKey] = []

    init(directory: URL? = nil) throws {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DivineMarssh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("known_hosts.json")
        self.hostKeys = Self.loadFromDisk(url: fileURL)
        Self.excludeFromBackup(url: fileURL)
    }

    private static func loadFromDisk(url: URL) -> [SSHHostKey] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SSHHostKey].self, from: data)) ?? []
    }

    private func saveToDisk() throws {
        let data = try JSONEncoder().encode(hostKeys)
        try data.write(to: fileURL, options: .atomic)
        Self.excludeFromBackup(url: fileURL)
    }

    private static func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }

    // MARK: - Query

    func lookup(hostname: String, port: UInt16, keyType: String) -> SSHHostKey? {
        hostKeys.first { $0.hostname == hostname && $0.port == port && $0.keyType == keyType }
    }

    /// All pinned keys for a host/port, across every key type. Used to pin per
    /// host rather than per (host, type), so a server presenting a different
    /// host-key algorithm than the one stored cannot bypass verification.
    func lookupAll(hostname: String, port: UInt16) -> [SSHHostKey] {
        hostKeys.filter { $0.hostname == hostname && $0.port == port }
    }

    func allHostKeys() -> [SSHHostKey] {
        hostKeys
    }

    // MARK: - Mutate

    func trust(hostKey: SSHHostKey) throws {
        hostKeys.removeAll { $0.id == hostKey.id }
        hostKeys.append(hostKey)
        try saveToDisk()
    }

    func revoke(hostname: String, port: UInt16) throws {
        hostKeys.removeAll { $0.hostname == hostname && $0.port == port }
        try saveToDisk()
    }
}
