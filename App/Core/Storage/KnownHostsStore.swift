import Foundation

enum KnownHostsStoreError: Error, Equatable {
    case storeUnreadable
}

actor KnownHostsStore {
    private let fileURL: URL
    private var hostKeys: [SSHHostKey] = []
    private let isUnreadable: Bool

    init(directory: URL? = nil) throws {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DivineMarssh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("known_hosts.json")
        self.fileURL = url
        switch Self.loadFromDisk(url: url) {
        case .success(let keys):
            self.hostKeys = keys
            self.isUnreadable = false
        case .failure:
            self.hostKeys = []
            self.isUnreadable = true
        }
        Self.excludeFromBackup(url: url)
    }

    private static func loadFromDisk(url: URL) -> Result<[SSHHostKey], Error> {
        do {
            let data = try Data(contentsOf: url)
            return .success(try JSONDecoder().decode([SSHHostKey].self, from: data))
        } catch {
            return isFileMissing(error) ? .success([]) : .failure(error)
        }
    }

    private static func isFileMissing(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        case NSPOSIXErrorDomain:
            return nsError.code == Int(ENOENT)
        default:
            return false
        }
    }

    private func saveToDisk(_ keys: [SSHHostKey]) throws {
        let data = try JSONEncoder().encode(keys)
        try data.write(to: fileURL, options: .atomic)
        Self.excludeFromBackup(url: fileURL)
    }

    private static func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }

    static func canonicalHostname(_ hostname: String) -> String {
        var canonical = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while canonical.hasSuffix(".") {
            canonical.removeLast()
        }
        if canonical.hasPrefix("["), canonical.hasSuffix("]") {
            canonical = String(canonical.dropFirst().dropLast())
        }
        return canonical
    }

    private func requireReadableStore() throws {
        guard !isUnreadable else { throw KnownHostsStoreError.storeUnreadable }
    }

    // MARK: - Query

    func lookup(hostname: String, port: UInt16, keyType: String) throws -> SSHHostKey? {
        try requireReadableStore()
        let target = Self.canonicalHostname(hostname)
        return hostKeys.first {
            Self.canonicalHostname($0.hostname) == target && $0.port == port && $0.keyType == keyType
        }
    }

    /// All pinned keys for a host/port, across every key type. Used to pin per
    /// host rather than per (host, type), so a server presenting a different
    /// host-key algorithm than the one stored cannot bypass verification.
    func lookupAll(hostname: String, port: UInt16) throws -> [SSHHostKey] {
        try requireReadableStore()
        let target = Self.canonicalHostname(hostname)
        return hostKeys.filter { Self.canonicalHostname($0.hostname) == target && $0.port == port }
    }

    func allHostKeys() throws -> [SSHHostKey] {
        try requireReadableStore()
        return hostKeys
    }

    // MARK: - Mutate

    func trust(hostKey: SSHHostKey) throws {
        try requireReadableStore()
        let canonical = SSHHostKey(
            hostname: Self.canonicalHostname(hostKey.hostname),
            port: hostKey.port,
            keyType: hostKey.keyType,
            publicKeyData: hostKey.publicKeyData,
            fingerprint: hostKey.fingerprint,
            firstSeenDate: hostKey.firstSeenDate
        )
        var updated = hostKeys
        updated.removeAll {
            Self.canonicalHostname($0.hostname) == canonical.hostname
                && $0.port == canonical.port
                && $0.keyType == canonical.keyType
        }
        updated.append(canonical)
        try saveToDisk(updated)
        hostKeys = updated
    }

    func revoke(hostname: String, port: UInt16) throws {
        try requireReadableStore()
        let target = Self.canonicalHostname(hostname)
        var updated = hostKeys
        updated.removeAll { Self.canonicalHostname($0.hostname) == target && $0.port == port }
        try saveToDisk(updated)
        hostKeys = updated
    }
}
