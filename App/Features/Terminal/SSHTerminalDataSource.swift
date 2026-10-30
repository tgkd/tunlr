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
    var allowRemoteClipboardWrite: Bool = false

    private let sshSession: SSHSession
    private var outputTask: Task<Void, Never>?
    private var resizeDebounceTask: Task<Void, Never>?
    private weak var terminalView: TerminalView?
    private var oscObservation: TerminalOscObservation?

    private(set) var currentTitle: String = ""
    private(set) var currentScrollPosition: Double = 0.0
    private(set) var lastSentData: ArraySlice<UInt8>?
    private(set) var pendingResize: (cols: Int, rows: Int)?

    private var outputBuffer: [UInt8] = []
    private var flushTask: Task<Void, Never>?

    init(sshSession: SSHSession) {
        self.sshSession = sshSession
        super.init()
    }

    func attachTerminalView(_ terminalView: TerminalView) {
        self.terminalView = terminalView
        terminalView.terminalDelegate = self
        observeOscEvents(terminalView)
        beginShellOutputFeed()
    }

    private func beginShellOutputFeed() {
        outputTask?.cancel()
        let cellSize = cellPixelSize()
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.sshSession.setCellPixelSize(width: cellSize.width, height: cellSize.height)
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
        flushTask?.cancel()
        flushTask = nil
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
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        Task { @MainActor [weak self] in
            guard let self, self.allowRemoteClipboardWrite else { return }
            guard let text = String(data: content, encoding: .utf8) else { return }
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: text]],
                options: [.expirationDate: Date().addingTimeInterval(60)]
            )
        }
    }
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func handleResizeForTesting(cols: Int, rows: Int) {
        handleResize(cols: cols, rows: rows)
    }

    // MARK: - Private

    private func observeOscEvents(_ terminalView: TerminalView) {
        oscObservation = terminalView.observeOscEvents { [weak self] oscEvent in
            guard let event = Self.terminalEvent(from: oscEvent) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.dataSource(self, didEmitEvent: event)
            }
        }
    }

    private nonisolated static func terminalEvent(from oscEvent: TerminalOscEvent) -> TerminalEvent? {
        let str = String(bytes: oscEvent.payload, encoding: .utf8) ?? ""
        switch oscEvent.code {
        case 133:
            return switch str {
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
        case 777:
            let parts = str.split(separator: ";", maxSplits: 2)
            guard parts.first == "notify", parts.count >= 3 else { return nil }
            return .notification(title: String(parts[1]), body: String(parts[2]))
        default:
            return nil
        }
    }

    private func handleOutput(_ output: ShellOutput) {
        let bytes: [UInt8]
        switch output {
        case .stdout(let data): bytes = Array(data)
        case .stderr(let data): bytes = Array(data)
        }
        outputBuffer.append(contentsOf: bytes)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, !Task.isCancelled else { return }
            let data = self.outputBuffer
            MemoryHygiene.zeroOut(&self.outputBuffer)
            self.flushTask = nil
            self.terminalView?.feed(byteArray: ArraySlice(data))
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
            let cellSize = self.cellPixelSize()
            await self.sshSession.setCellPixelSize(width: cellSize.width, height: cellSize.height)
            try? await self.sshSession.sendWindowChange(cols: resize.cols, rows: resize.rows)
        }
    }

    private func cellPixelSize() -> (width: Int, height: Int) {
        guard let terminalView else { return (width: 0, height: 0) }
        let font = terminalView.font
        let scale = max(terminalView.traitCollection.displayScale, 1)
        let advance = ("W" as NSString).size(withAttributes: [.font: font]).width
        return (
            width: Int((advance * scale).rounded(.up)),
            height: Int((font.lineHeight * scale).rounded(.up))
        )
    }

    deinit {
        outputTask?.cancel()
        resizeDebounceTask?.cancel()
        flushTask?.cancel()
    }
}
