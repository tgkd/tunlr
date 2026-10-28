import Testing
import Foundation
@testable import DivineMarssh

private let pathPrefix = "export PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\"; "

@Suite("ShellQuote")
struct ShellQuoteTests {
    @Test func quotesPlainValue() {
        #expect(ShellQuote.quote("main") == "'main'")
    }

    @Test func escapesSingleQuote() {
        #expect(ShellQuote.quote("it's my session") == "'it'\\''s my session'")
    }

    @Test func quotesEmptyValue() {
        #expect(ShellQuote.quote("") == "''")
    }
}

@Suite("TmuxSessionBackend")
struct TmuxSessionBackendTests {
    let backend = TmuxSessionBackend()

    @Test func listCommandPutsTheNameLast() {
        #expect(backend.listCommand == pathPrefix + "tmux -u list-sessions -F '#{session_id} #{session_windows} #{session_attached} #{session_name}' 2>/dev/null")
        #expect(!backend.listCommand.contains("\t"))
    }

    @Test func parsesMultipleSessions() {
        let output = "$0 2 1 main\n$3 1 0 work stuff\n$7 5 2 logs\n"
        let entries = backend.parse(listOutput: output)
        #expect(entries.count == 3)
        #expect(entries[0] == RemoteSessionEntry(
            backend: .tmux,
            targetID: "$0",
            name: "main",
            detail: "2 windows, attached",
            attachCommand: pathPrefix + "tmux -u attach-session -t '$0'"
        ))
        #expect(entries[1].targetID == "$3")
        #expect(entries[1].name == "work stuff")
        #expect(entries[1].detail == "1 window")
        #expect(entries[2].detail == "5 windows, attached")
        #expect(entries[2].id == "tmux:$7")
    }

    @Test func ignoresMalformedLines() {
        let output = "garbage line\n$1 3 only\n$2 1 0 ok\nwork 1 0 nodollar\n$4 x 0 bad\n$5 1 0 \n"
        let entries = backend.parse(listOutput: output)
        #expect(entries.map(\.targetID) == ["$2"])
    }

    @Test func handlesCarriageReturns() {
        let entries = backend.parse(listOutput: "$1 1 0 one\r\n$2 2 0 two\r\n")
        #expect(entries.map(\.name) == ["one", "two"])
        #expect(entries[1].detail == "2 windows")
    }

    @Test func emptyOutputYieldsNothing() {
        #expect(backend.parse(listOutput: "").isEmpty)
        #expect(backend.parse(listOutput: "\n\n").isEmpty)
    }

    @Test func noServerOutputYieldsNothing() {
        #expect(backend.parse(listOutput: "no server running on /tmp/tmux-501/default\n").isEmpty)
    }

    @Test func attachQuotesSessionID() {
        let entries = backend.parse(listOutput: "$12 1 0 it's mine")
        #expect(entries.first?.attachCommand == pathPrefix + "tmux -u attach-session -t '$12'")
        #expect(entries.first?.attachCommand.contains("new") == false)
    }

    @Test func createQuotesName() {
        #expect(backend.createCommand(name: "it's my session") == pathPrefix + "tmux new-session -d -s 'it'\\''s my session'")
    }
}

@Suite("ZmxSessionBackend")
struct ZmxSessionBackendTests {
    let backend = ZmxSessionBackend()

    @Test func listCommand() {
        #expect(backend.listCommand == pathPrefix + "zmx list 2>/dev/null")
    }

    @Test func parsesRealOutput() {
        let output = """
          name=probe-one\tpid=92147\tclients=0\tcreated=1793168779\tcwd=file://host/Users/me/proj\tended=1793168779\texit_code=0
          name=api\tpid=92200\tclients=1\tcreated=1793168800\tcwd=file://host/Users/me/api
          name=build\tpid=92300\tclients=3\tcreated=1793168900\tcwd=file://host/Users/me/build

        """
        let entries = backend.parse(listOutput: output)
        #expect(entries.count == 3)
        #expect(entries[0] == RemoteSessionEntry(
            backend: .zmx,
            targetID: "probe-one",
            name: "probe-one",
            detail: "0 clients",
            attachCommand: pathPrefix + "zmx attach 'probe-one'"
        ))
        #expect(entries[1].detail == "1 client")
        #expect(entries[2].detail == "3 clients")
    }

    @Test func noSessionsMessageYieldsNothing() {
        #expect(backend.parse(listOutput: "No sessions found in /tmp/zmx-501\n").isEmpty)
    }

    @Test func emptyOutputYieldsNothing() {
        #expect(backend.parse(listOutput: "").isEmpty)
    }

    @Test func ignoresLinesWithoutName() {
        let output = "  pid=1\tclients=0\n  name=\tpid=2\n  name=ok\tpid=3\n"
        #expect(backend.parse(listOutput: output).map(\.name) == ["ok"])
    }

    @Test func missingClientsGivesEmptyDetail() {
        let entries = backend.parse(listOutput: "  name=solo\tpid=5\n")
        #expect(entries.first?.detail == "")
    }

    @Test func keepsEqualsSignInValue() {
        let entries = backend.parse(listOutput: "  name=a=b\tclients=0\n")
        #expect(entries.first?.name == "a=b")
    }

    @Test func attachQuotesName() {
        let entries = backend.parse(listOutput: "  name=it's mine\tclients=0\n")
        #expect(entries.first?.attachCommand == pathPrefix + "zmx attach 'it'\\''s mine'")
    }

    @Test func createIsUnavailable() {
        #expect(backend.createCommand(name: "anything") == nil)
    }
}

@Suite("AgtermSessionBackend")
struct AgtermSessionBackendTests {
    let backend = AgtermSessionBackend()

    static let splitTree = """
    {"ok":true,"result":{"remote":{"endpoint":{"executable":"/Applications/agterm.app/Contents/MacOS/zmx","socketDirectory":"/tmp/agterm-zmx-4c772f2cd3eb8240"},"presentation":1,"sessions":[{"id":"A887A05D-0000","name":"api","windowID":"W1","windowName":"window 1","workspaceID":"WS1","workspaceName":"work","cwd":"/Users/me/api","splitAxis":"vertical","status":"active","context":{"branch":"main"},"panes":[{"pane":"left","daemon":"agterm-09e7","foreground":["claude"]},{"pane":"right","daemon":"agterm-1b19","foreground":["zsh"]}]},{"id":"B000","name":"notes","windowID":"W1","windowName":"window 1","workspaceID":"WS2","workspaceName":"home","cwd":"/Users/me","panes":[{"pane":"left","daemon":"agterm-aaaa","foreground":["vim","todo.md"]}]}]}}}
    """

    @Test func listCommand() {
        #expect(backend.listCommand == pathPrefix + "agtermctl zmx tree --json 2>/dev/null")
    }

    @Test func parsesSplitSessionAsOneEntryPerPane() {
        let entries = backend.parse(listOutput: Self.splitTree)
        #expect(entries.count == 3)
        #expect(entries[0] == RemoteSessionEntry(
            backend: .agterm,
            targetID: "agterm-09e7",
            name: "api",
            detail: "work · claude",
            attachCommand: pathPrefix + "ZMX_DIR='/tmp/agterm-zmx-4c772f2cd3eb8240' '/Applications/agterm.app/Contents/MacOS/zmx' attach 'agterm-09e7'"
        ))
        #expect(entries[1].targetID == "agterm-1b19")
        #expect(entries[1].name == "api (right)")
        #expect(entries[1].detail == "work · zsh")
    }

    @Test func singlePaneSessionHasNoSuffix() {
        let entries = backend.parse(listOutput: Self.splitTree)
        #expect(entries[2].name == "notes")
        #expect(entries[2].detail == "home · vim todo.md")
    }

    @Test func singleNonLeftPaneHasNoSuffix() {
        let json = """
        {"ok":true,"result":{"remote":{"endpoint":{"executable":"/z","socketDirectory":"/s"},"sessions":[{"name":"solo","workspaceName":"w","panes":[{"pane":"right","daemon":"d1"}]}]}}}
        """
        #expect(backend.parse(listOutput: json).map(\.name) == ["solo"])
    }

    @Test func missingOptionalsStillParse() {
        let json = """
        {"ok":true,"result":{"remote":{"endpoint":{"executable":"/z","socketDirectory":"/s"},"sessions":[{"id":"X","name":"bare","workspaceName":"w","panes":[{"pane":"left","daemon":"d1"},{"pane":"bottom","daemon":"d2","foreground":[]}]}]}}}
        """
        let entries = backend.parse(listOutput: json)
        #expect(entries.count == 2)
        #expect(entries[0].detail == "w")
        #expect(entries[1].name == "bare (bottom)")
        #expect(entries[1].detail == "w")
    }

    @Test func attachQuotesPathsWithSpacesAndQuotes() {
        let json = """
        {"ok":true,"result":{"remote":{"endpoint":{"executable":"/Apps/my term.app/zmx","socketDirectory":"/tmp/it's dir"},"sessions":[{"name":"s","workspaceName":"w","panes":[{"pane":"left","daemon":"d'1"}]}]}}}
        """
        let entries = backend.parse(listOutput: json)
        #expect(entries.first?.attachCommand == pathPrefix + "ZMX_DIR='/tmp/it'\\''s dir' '/Apps/my term.app/zmx' attach 'd'\\''1'")
    }

    @Test func notOkYieldsNothing() {
        let json = """
        {"ok":false,"error":{"message":"not running"}}
        """
        #expect(backend.parse(listOutput: json).isEmpty)
    }

    @Test func invalidJSONYieldsNothing() {
        #expect(backend.parse(listOutput: "{not json").isEmpty)
        #expect(backend.parse(listOutput: "").isEmpty)
        #expect(backend.parse(listOutput: "{\"ok\":true,\"result\":{\"remote\":{\"sessions\":[]}}}").isEmpty)
    }

    @Test func emptySessionsYieldsNothing() {
        let json = """
        {"ok":true,"result":{"remote":{"endpoint":{"executable":"/z","socketDirectory":"/s"},"presentation":1,"sessions":[]}}}
        """
        #expect(backend.parse(listOutput: json).isEmpty)
    }

    @Test func createIsUnavailable() {
        #expect(backend.createCommand(name: "anything") == nil)
    }
}

@Suite("RemoteSessionBackends")
struct RemoteSessionBackendsTests {
    @Test func allBackendsInOrder() {
        #expect(RemoteSessionBackends.all.map(\.kind) == [.tmux, .zmx, .agterm])
    }

    @Test func everyCommandStartsWithPathPrefix() {
        for backend in RemoteSessionBackends.all {
            #expect(backend.listCommand.hasPrefix(pathPrefix))
        }
        #expect(TmuxSessionBackend().createCommand(name: "x")?.hasPrefix(pathPrefix) == true)
        let tmuxEntries = TmuxSessionBackend().parse(listOutput: "$1 1 0 x")
        let zmxEntries = ZmxSessionBackend().parse(listOutput: "  name=x\tclients=0")
        let agtermEntries = AgtermSessionBackend().parse(listOutput: AgtermSessionBackendTests.splitTree)
        for entry in tmuxEntries + zmxEntries + agtermEntries {
            #expect(entry.attachCommand.hasPrefix(pathPrefix))
        }
    }
}

private struct DiscoveryRunnerError: Error {}

private struct FakeRemoteCommandRunner: RemoteCommandRunning {
    enum Response: Sendable {
        case output(String, status: Int)
        case failure
    }

    let responses: [String: Response]

    func runCommand(_ command: String) async throws -> CommandResult {
        switch responses[command] {
        case .output(let text, let status):
            return CommandResult(stdout: Data(text.utf8), stderr: Data(), termination: .exited(status: status))
        case .failure, nil:
            throw DiscoveryRunnerError()
        }
    }
}

private struct FakeSessionBackend: RemoteSessionBackend {
    let kind: SessionBackendKind
    let listCommand: String

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        RemoteShellLines.split(listOutput).map { name in
            RemoteSessionEntry(backend: kind, targetID: "\(listCommand)-\(name)", name: name, detail: "", attachCommand: "attach \(name)")
        }
    }

    func createCommand(name: String) -> String? {
        nil
    }
}

private enum RemoteShellLines {
    static func split(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init)
    }
}

@Suite("RemoteSessionDiscovery")
struct RemoteSessionDiscoveryTests {
    @Test func mergesBackendsInOrderSortedByName() async {
        let runner = FakeRemoteCommandRunner(responses: [
            TmuxSessionBackend().listCommand: .failure,
            ZmxSessionBackend().listCommand: .output("  name=zeta\tclients=0\n  name=alpha\tclients=1\n", status: 0),
            AgtermSessionBackend().listCommand: .output(AgtermSessionBackendTests.splitTree, status: 0),
        ])
        let entries = await RemoteSessionDiscovery().discover(using: runner)
        #expect(entries.map(\.backend) == [.zmx, .zmx, .agterm, .agterm, .agterm])
        #expect(entries.map(\.name) == ["alpha", "zeta", "api", "api (right)", "notes"])
    }

    @Test func parsesOutputRegardlessOfExitStatus() async {
        let runner = FakeRemoteCommandRunner(responses: [
            TmuxSessionBackend().listCommand: .output("$1 1 0 main\n", status: 1),
        ])
        let entries = await RemoteSessionDiscovery().discover(using: runner)
        #expect(entries.map(\.id) == ["tmux:$1"])
    }

    @Test func emptyOutputYieldsNoEntries() async {
        let runner = FakeRemoteCommandRunner(responses: [
            TmuxSessionBackend().listCommand: .output("", status: 1),
            ZmxSessionBackend().listCommand: .output("   \n", status: 0),
            AgtermSessionBackend().listCommand: .output("", status: 127),
        ])
        let entries = await RemoteSessionDiscovery().discover(using: runner)
        #expect(entries.isEmpty)
    }

    @Test func allBackendsFailingYieldsEmpty() async {
        let entries = await RemoteSessionDiscovery().discover(using: FakeRemoteCommandRunner(responses: [:]))
        #expect(entries.isEmpty)
    }

    @Test func ordersByBackendPositionNotKind() async {
        let discovery = RemoteSessionDiscovery(backends: [
            FakeSessionBackend(kind: .agterm, listCommand: "first"),
            FakeSessionBackend(kind: .tmux, listCommand: "broken"),
            FakeSessionBackend(kind: .tmux, listCommand: "second"),
        ])
        let runner = FakeRemoteCommandRunner(responses: [
            "first": .output("delta\nbeta\n", status: 0),
            "broken": .failure,
            "second": .output("Charlie\nalpha\nbravo\n", status: 0),
        ])
        let entries = await discovery.discover(using: runner)
        #expect(entries.map(\.name) == ["beta", "delta", "alpha", "bravo", "Charlie"])
        #expect(entries.map(\.backend) == [.agterm, .agterm, .tmux, .tmux, .tmux])
    }
}
