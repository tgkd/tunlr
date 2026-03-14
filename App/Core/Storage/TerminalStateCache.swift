import Foundation

struct CachedTerminalState: Codable, Sendable, Equatable {
    let profileID: UUID
    let ptyConfiguration: CachedPTYConfiguration
    let terminalTitle: String
    let cursorRow: Int
    let cursorCol: Int
    let scrollbackLineCount: Int
    let screenContent: [String]
    let timestamp: Date
    let wasExplicitQuit: Bool

    struct CachedPTYConfiguration: Codable, Sendable, Equatable {
        let cols: Int
        let rows: Int
        let term: String

        init(cols: Int, rows: Int, term: String = "xterm-256color") {
            self.cols = cols
            self.rows = rows
            self.term = term
        }
    }
}

actor TerminalStateCache {
    private let cacheDirectory: URL
    private static let fileName = "terminal_state.json"

    init(directory: URL? = nil) throws {
        let dir = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DivineMarssh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
    }

    var fileURL: URL {
        cacheDirectory.appendingPathComponent(Self.fileName)
    }

    func save(_ state: CachedTerminalState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() -> CachedTerminalState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedTerminalState.self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func hasState() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}
