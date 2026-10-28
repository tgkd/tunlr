import Foundation

enum SessionBackendKind: String, Codable, Sendable, CaseIterable {
    case tmux
    case zmx
    case agterm

    var displayName: String {
        switch self {
        case .tmux: "tmux"
        case .zmx: "zmx"
        case .agterm: "agterm"
        }
    }

    var isExperimental: Bool {
        self != .tmux
    }
}

struct RemoteSessionEntry: Sendable, Equatable, Hashable, Identifiable {
    let backend: SessionBackendKind
    let targetID: String
    let name: String
    let detail: String
    let attachCommand: String

    var id: String { "\(backend.rawValue):\(targetID)" }
}

enum SessionAttachPreference: Codable, Sendable, Equatable {
    case shell
    case pick
    case always(backend: SessionBackendKind, name: String)
}

struct RemoteSessionChoice: Sendable, Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let entries: [RemoteSessionEntry]
    let missingName: String?

    init(id: UUID = UUID(), profileID: UUID, entries: [RemoteSessionEntry], missingName: String? = nil) {
        self.id = id
        self.profileID = profileID
        self.entries = entries
        self.missingName = missingName
    }
}

protocol RemoteCommandRunning: Sendable {
    func runCommand(_ command: String) async throws -> CommandResult
}

extension SSHSession: RemoteCommandRunning {}

protocol RemoteSessionBackend: Sendable {
    var kind: SessionBackendKind { get }
    var listCommand: String { get }
    func parse(listOutput: String) -> [RemoteSessionEntry]
    func createCommand(name: String) -> String?
}
