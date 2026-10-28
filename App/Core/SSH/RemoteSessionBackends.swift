import Foundation

enum ShellQuote {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct TmuxSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.tmux
    let listCommand = ""

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        []
    }

    func createCommand(name: String) -> String? {
        nil
    }
}

struct ZmxSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.zmx
    let listCommand = ""

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        []
    }

    func createCommand(name: String) -> String? {
        nil
    }
}

struct AgtermSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.agterm
    let listCommand = ""

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        []
    }

    func createCommand(name: String) -> String? {
        nil
    }
}

enum RemoteSessionBackends {
    static let all: [any RemoteSessionBackend] = [
        TmuxSessionBackend(),
        ZmxSessionBackend(),
        AgtermSessionBackend(),
    ]
}
