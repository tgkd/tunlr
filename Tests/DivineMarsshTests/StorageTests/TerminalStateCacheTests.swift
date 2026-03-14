import Testing
import Foundation
@testable import DivineMarssh

struct TerminalStateCacheTests {

    private func makeCache() throws -> (TerminalStateCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = try TerminalStateCache(directory: dir)
        return (cache, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeSampleState(
        profileID: UUID = UUID(),
        wasExplicitQuit: Bool = false,
        cols: Int = 80,
        rows: Int = 24
    ) -> CachedTerminalState {
        CachedTerminalState(
            profileID: profileID,
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(
                cols: cols,
                rows: rows,
                term: "xterm-256color"
            ),
            terminalTitle: "user@host",
            cursorRow: 5,
            cursorCol: 10,
            scrollbackLineCount: 100,
            screenContent: ["$ ls", "file1.txt  file2.txt", "$ "],
            timestamp: Date(),
            wasExplicitQuit: wasExplicitQuit
        )
    }

    // MARK: - Save and Load

    @Test func saveAndLoadRoundTrip() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let state = makeSampleState()
        try await cache.save(state)

        let loaded = await cache.load()
        #expect(loaded != nil)
        #expect(loaded?.profileID == state.profileID)
        #expect(loaded?.ptyConfiguration.cols == 80)
        #expect(loaded?.ptyConfiguration.rows == 24)
        #expect(loaded?.ptyConfiguration.term == "xterm-256color")
        #expect(loaded?.terminalTitle == "user@host")
        #expect(loaded?.cursorRow == 5)
        #expect(loaded?.cursorCol == 10)
        #expect(loaded?.scrollbackLineCount == 100)
        #expect(loaded?.screenContent == ["$ ls", "file1.txt  file2.txt", "$ "])
        #expect(loaded?.wasExplicitQuit == false)
    }

    @Test func loadReturnsNilWhenNoState() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let loaded = await cache.load()
        #expect(loaded == nil)
    }

    @Test func hasStateReturnsFalseWhenEmpty() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let has = await cache.hasState()
        #expect(!has)
    }

    @Test func hasStateReturnsTrueAfterSave() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        try await cache.save(makeSampleState())
        let has = await cache.hasState()
        #expect(has)
    }

    // MARK: - Clear

    @Test func clearRemovesState() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        try await cache.save(makeSampleState())
        #expect(await cache.hasState())

        await cache.clear()
        #expect(await cache.load() == nil)
        #expect(await !cache.hasState())
    }

    // MARK: - Explicit Quit Flag

    @Test func explicitQuitFlagPreserved() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let state = makeSampleState(wasExplicitQuit: true)
        try await cache.save(state)

        let loaded = await cache.load()
        #expect(loaded?.wasExplicitQuit == true)
    }

    @Test func nonExplicitQuitFlagPreserved() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let state = makeSampleState(wasExplicitQuit: false)
        try await cache.save(state)

        let loaded = await cache.load()
        #expect(loaded?.wasExplicitQuit == false)
    }

    // MARK: - Overwrite

    @Test func saveOverwritesPreviousState() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let id1 = UUID()
        let id2 = UUID()

        try await cache.save(makeSampleState(profileID: id1))
        try await cache.save(makeSampleState(profileID: id2))

        let loaded = await cache.load()
        #expect(loaded?.profileID == id2)
    }

    // MARK: - PTY Configuration

    @Test func ptyConfigurationRoundTrip() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let state = makeSampleState(cols: 120, rows: 40)
        try await cache.save(state)

        let loaded = await cache.load()
        #expect(loaded?.ptyConfiguration.cols == 120)
        #expect(loaded?.ptyConfiguration.rows == 40)
    }

    // MARK: - Codable Model

    @Test func cachedTerminalStateEquatable() {
        let id = UUID()
        let date = Date()
        let state1 = CachedTerminalState(
            profileID: id,
            ptyConfiguration: .init(cols: 80, rows: 24),
            terminalTitle: "title",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: date,
            wasExplicitQuit: false
        )
        let state2 = CachedTerminalState(
            profileID: id,
            ptyConfiguration: .init(cols: 80, rows: 24),
            terminalTitle: "title",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: date,
            wasExplicitQuit: false
        )
        #expect(state1 == state2)
    }

    @Test func cachedTerminalStateNotEqualDifferentProfile() {
        let date = Date()
        let state1 = CachedTerminalState(
            profileID: UUID(),
            ptyConfiguration: .init(cols: 80, rows: 24),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: date,
            wasExplicitQuit: false
        )
        let state2 = CachedTerminalState(
            profileID: UUID(),
            ptyConfiguration: .init(cols: 80, rows: 24),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: date,
            wasExplicitQuit: false
        )
        #expect(state1 != state2)
    }

    // MARK: - JSON Encoding Verification

    @Test func stateIsStoredAsJSON() async throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let state = makeSampleState()
        try await cache.save(state)

        let fileURL = await cache.fileURL
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["profileID"] != nil)
        #expect(json?["wasExplicitQuit"] != nil)
    }

    // MARK: - Persistence Across Instances

    @Test func persistenceAcrossCacheInstances() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { cleanup(dir) }

        let profileID = UUID()

        let cache1 = try TerminalStateCache(directory: dir)
        try await cache1.save(makeSampleState(profileID: profileID))

        let cache2 = try TerminalStateCache(directory: dir)
        let loaded = await cache2.load()
        #expect(loaded?.profileID == profileID)
    }
}
