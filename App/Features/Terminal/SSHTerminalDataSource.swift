import Foundation
import SwiftTerm
import UIKit

protocol SSHTerminalDataSourceDelegate: AnyObject {
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateTitle title: String)
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateScrollPosition position: Double)
    @MainActor func dataSource(_ dataSource: SSHTerminalDataSource, didRequestOpenLink link: String)
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
            self?.currentScrollPosition = position
            self?.delegate?.dataSource(self!, didUpdateScrollPosition: position)
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

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.dataSource(self, didRequestOpenLink: link)
        }
    }

    nonisolated func bell(source: TerminalView) {}
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {}
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func handleResizeForTesting(cols: Int, rows: Int) {
        handleResize(cols: cols, rows: rows)
    }

    // MARK: - Private

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
