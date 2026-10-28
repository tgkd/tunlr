import Foundation

enum ShellQuote {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum RemoteShell {
    static let pathPrefix = "export PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\"; "

    static func command(_ body: String) -> String {
        pathPrefix + body
    }

    static func lines(_ output: String) -> [Substring] {
        output.split(whereSeparator: \.isNewline)
    }

    static func plural(_ count: Int, _ singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }
}

struct TmuxSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.tmux
    let listCommand = RemoteShell.command(
        "tmux -u list-sessions -F "
            + ShellQuote.quote("#{session_id} #{session_windows} #{session_attached} #{session_name}")
            + " 2>/dev/null"
    )

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        RemoteShell.lines(listOutput).compactMap(entry(from:))
    }

    func createCommand(name: String) -> String? {
        RemoteShell.command("tmux new-session -d -s \(ShellQuote.quote(name))")
    }

    private func entry(from line: Substring) -> RemoteSessionEntry? {
        let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4 else { return nil }
        let sessionID = fields[0]
        let name = fields[3]
        guard sessionID.hasPrefix("$"), !name.isEmpty,
              let windows = Int(fields[1]),
              let attached = Int(fields[2]) else {
            return nil
        }
        var detail = RemoteShell.plural(windows, "window")
        if attached > 0 {
            detail += ", attached"
        }
        return RemoteSessionEntry(
            backend: kind,
            targetID: sessionID,
            name: name,
            detail: detail,
            attachCommand: RemoteShell.command("tmux -u attach-session -t \(ShellQuote.quote(sessionID))")
        )
    }
}

struct ZmxSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.zmx
    let listCommand = RemoteShell.command("zmx list 2>/dev/null")

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        RemoteShell.lines(listOutput).compactMap(entry(from:))
    }

    func createCommand(name: String) -> String? {
        nil
    }

    private func entry(from line: Substring) -> RemoteSessionEntry? {
        let values = keyValues(of: line)
        guard let name = values["name"], !name.isEmpty else { return nil }
        let detail = values["clients"].flatMap { Int($0) }.map { RemoteShell.plural($0, "client") } ?? ""
        return RemoteSessionEntry(
            backend: kind,
            targetID: name,
            name: name,
            detail: detail,
            attachCommand: RemoteShell.command("zmx attach \(ShellQuote.quote(name))")
        )
    }

    private func keyValues(of line: Substring) -> [String: String] {
        var result: [String: String] = [:]
        for field in line.split(separator: "\t") {
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            guard let key = parts[0].split(whereSeparator: \.isWhitespace).last else { continue }
            result[String(key)] = String(parts[1])
        }
        return result
    }
}

struct AgtermSessionBackend: RemoteSessionBackend {
    let kind = SessionBackendKind.agterm
    let listCommand = RemoteShell.command("agtermctl zmx tree --json 2>/dev/null")

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        guard let response = try? JSONDecoder().decode(TreeResponse.self, from: Data(listOutput.utf8)),
              response.ok,
              let remote = response.result?.remote else {
            return []
        }
        let endpoint = remote.endpoint
        return (remote.sessions ?? []).flatMap { session in
            entries(for: session, endpoint: endpoint)
        }
    }

    func createCommand(name: String) -> String? {
        nil
    }

    private func entries(for session: TreeSession, endpoint: TreeEndpoint) -> [RemoteSessionEntry] {
        let panes = session.panes ?? []
        return panes.map { pane in
            var name = session.name
            if panes.count > 1, let paneName = pane.pane, paneName != "left" {
                name += " (\(paneName))"
            }
            var detailParts: [String] = []
            if let workspace = session.workspaceName, !workspace.isEmpty {
                detailParts.append(workspace)
            }
            if let foreground = pane.foreground, !foreground.isEmpty {
                detailParts.append(foreground.joined(separator: " "))
            }
            let attach = "ZMX_DIR=\(ShellQuote.quote(endpoint.socketDirectory)) "
                + "\(ShellQuote.quote(endpoint.executable)) attach \(ShellQuote.quote(pane.daemon))"
            return RemoteSessionEntry(
                backend: kind,
                targetID: pane.daemon,
                name: name,
                detail: detailParts.joined(separator: " · "),
                attachCommand: RemoteShell.command(attach)
            )
        }
    }

    private struct TreeResponse: Decodable {
        let ok: Bool
        let result: TreeResult?
    }

    private struct TreeResult: Decodable {
        let remote: TreeRemote?
    }

    private struct TreeRemote: Decodable {
        let endpoint: TreeEndpoint
        let sessions: [TreeSession]?
    }

    private struct TreeEndpoint: Decodable {
        let executable: String
        let socketDirectory: String
    }

    private struct TreeSession: Decodable {
        let name: String
        let workspaceName: String?
        let panes: [TreePane]?
    }

    private struct TreePane: Decodable {
        let pane: String?
        let daemon: String
        let foreground: [String]?
    }
}

enum RemoteSessionBackends {
    static let all: [any RemoteSessionBackend] = [
        TmuxSessionBackend(),
        ZmxSessionBackend(),
        AgtermSessionBackend(),
    ]
}
