import Foundation
import SwiftTerm
import UIKit

protocol SSHTerminalDataSourceDelegate: AnyObject {
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateTitle title: String)
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateScrollPosition position: Double)
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didRequestOpenLink link: String)
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didEmitEvent event: TerminalEvent)
}

extension SSHTerminalDataSourceDelegate {
    func dataSource(_ dataSource: SSHTerminalDataSource, didEmitEvent event: TerminalEvent) {}
}

@MainActor
final class SSHTerminalDataSource: NSObject, TerminalViewDelegate {
    weak var delegate: SSHTerminalDataSourceDelegate?

    private let sshSession: SSHSession
    private var outputTask: Task<Void, Never>?
    private var resizeDebounceTask: Task<Void, Never>?
    private weak var terminalView: TerminalView?

    private(set) var currentTitle: String = ""
    private(set) var currentScrollPosition: Double = 0.0
    private(set) var lastSentData: ArraySlice<UInt8>?
    private(set) var pendingResize: (cols: Int, rows: Int)?

    init(sshSession: SSHSession) {
        self.sshSession = sshSession
        super.init()
    }

    func attachTerminalView(_ terminalView: TerminalView) {
        self.terminalView = terminalView
        terminalView.terminalDelegate = self
        registerOscHandlers(terminalView)
        beginShellOutputFeed()
    }

    private func beginShellOutputFeed() {
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.sshSession.openShellChannel()
                for await output in stream {
                    guard !Task.isCancelled else { break }
                    self.handleOutput(output)
                }
            } catch {
                let message = "\r\n\u{1B}[31mShell error: \(error.localizedDescription)\u{1B}[0m\r\n"
                self.terminalView?.feed(text: message)
            }
        }
    }

    func startOutputFeed(from stream: AsyncStream<ShellOutput>) {
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            for await output in stream {
                guard !Task.isCancelled else { break }
                await self?.handleOutput(output)
            }
        }
    }

    func stopOutputFeed() {
        outputTask?.cancel()
        outputTask = nil
    }

    // MARK: - TerminalViewDelegate

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let dataCopy = Array(data)
        Task { @MainActor [weak self] in
            self?.lastSentData = ArraySlice(dataCopy)
            guard let session = self?.sshSession else { return }
            try? await session.write(Data(dataCopy))
        }
    }

    nonisolated func scrolled(source: TerminalView, position: Double) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentScrollPosition = position
            self.delegate?.dataSource(self, didUpdateScrollPosition: position)
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentTitle = title
            self.delegate?.dataSource(self, didUpdateTitle: title)
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor [weak self] in
            self?.handleResize(cols: newCols, rows: newRows)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.dataSource(self, didEmitEvent: .directoryChanged(directory))
        }
    }

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.dataSource(self, didRequestOpenLink: link)
        }
    }

    nonisolated func bell(source: TerminalView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.dataSource(self, didEmitEvent: .bell)
        }
    }
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {}
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func handleResizeForTesting(cols: Int, rows: Int) {
        handleResize(cols: cols, rows: rows)
    }

    // MARK: - Private

    private func registerOscHandlers(_ terminalView: TerminalView) {
        let terminal = terminalView.getTerminal()

        terminal.registerOscHandler(code: 133) { [weak self] data in
            let str = String(bytes: data, encoding: .utf8) ?? ""
            let event: TerminalEvent? = switch str {
            case "A":
                .promptReady
            case "B":
                .commandStarted
            case "C":
                .commandFinished(exitCode: nil)
            case _ where str.hasPrefix("D"):
                .commandFinished(exitCode: str.split(separator: ";").dropFirst().first.flatMap { Int($0) })
            default:
                nil
            }
            if let event {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.delegate?.dataSource(self, didEmitEvent: event)
                }
            }
        }

        terminal.registerOscHandler(code: 777) { [weak self] data in
            let str = String(bytes: data, encoding: .utf8) ?? ""
            let parts = str.split(separator: ";", maxSplits: 2)
            guard parts.first == "notify", parts.count >= 3 else { return }
            let title = String(parts[1])
            let body = String(parts[2])
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.dataSource(self, didEmitEvent: .notification(title: title, body: body))
            }
        }
    }

    private func handleOutput(_ output: ShellOutput) {
        switch output {
        case .stdout(let data):
            terminalView?.feed(byteArray: ArraySlice(data))
        case .stderr(let data):
            terminalView?.feed(byteArray: ArraySlice(data))
        }
    }

    private func handleResize(cols: Int, rows: Int) {
        pendingResize = (cols: cols, rows: rows)
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            guard let self, let resize = self.pendingResize else { return }
            self.pendingResize = nil
            try? await self.sshSession.sendWindowChange(cols: resize.cols, rows: resize.rows)
        }
    }

    deinit {
        outputTask?.cancel()
        resizeDebounceTask?.cancel()
    }
}
