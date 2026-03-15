import Foundation

actor AppearanceStore {
    private let fileURL: URL
    private var appearance: TerminalAppearance

    init(directory: URL? = nil) throws {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DivineMarssh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("appearance.json")
        self.appearance = Self.loadFromDisk(url: fileURL)
    }

    private static func loadFromDisk(url: URL) -> TerminalAppearance {
        guard let data = try? Data(contentsOf: url) else { return TerminalAppearance() }
        return (try? JSONDecoder().decode(TerminalAppearance.self, from: data)) ?? TerminalAppearance()
    }

    private func saveToDisk() throws {
        let data = try JSONEncoder().encode(appearance)
        try data.write(to: fileURL, options: .atomic)
    }

    func currentAppearance() -> TerminalAppearance {
        appearance
    }

    func update(_ newAppearance: TerminalAppearance) throws {
        appearance = newAppearance
        try saveToDisk()
    }
}
