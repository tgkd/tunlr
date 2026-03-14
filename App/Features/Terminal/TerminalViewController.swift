import UIKit
import SwiftTerm

@MainActor
final class TerminalViewController: UIViewController {
    private(set) var terminalView: TerminalView!
    private(set) var dataSource: SSHTerminalDataSource

    var onTitleChange: ((String) -> Void)?
    var onSizeChange: ((Int, Int) -> Void)?

    init(dataSource: SSHTerminalDataSource) {
        self.dataSource = dataSource
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private(set) var keyboardAccessory: KeyboardAccessoryView?

    override func viewDidLoad() {
        super.viewDidLoad()

        terminalView = TerminalView(frame: .zero, font: nil)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        applyTerminalTheme()
        view.addSubview(terminalView)

        let hPadding: CGFloat = 12
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: hPadding),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -hPadding),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let short = UIDevice.current.userInterfaceIdiom == .phone
        let accessory = KeyboardAccessoryView(
            frame: CGRect(x: 0, y: 0, width: view.frame.width, height: short ? 44 : 48),
            terminalView: terminalView
        )
        keyboardAccessory = accessory
        terminalView.inputAccessoryView = accessory

        dataSource.attachTerminalView(terminalView)
        dataSource.delegate = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        notifyTerminalSize()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyTerminalTheme()
        }
    }

    private func applyTerminalTheme() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        if isDark {
            terminalView.nativeBackgroundColor = .black
            terminalView.nativeForegroundColor = UIColor(white: 0.9, alpha: 1.0)
            view.backgroundColor = .black
        } else {
            terminalView.nativeBackgroundColor = UIColor(white: 0.97, alpha: 1.0)
            terminalView.nativeForegroundColor = UIColor(white: 0.1, alpha: 1.0)
            view.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        }
    }

    func feedData(_ data: ArraySlice<UInt8>) {
        terminalView?.feed(byteArray: data)
    }

    func terminalSize() -> (cols: Int, rows: Int)? {
        guard let terminalView, terminalView.bounds.width > 0 else { return nil }
        let terminal = terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows
        guard cols > 0, rows > 0 else { return nil }
        return (cols: cols, rows: rows)
    }

    private func notifyTerminalSize() {
        guard let size = terminalSize() else { return }
        onSizeChange?(size.cols, size.rows)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            if let mapped = KeyMapping.hardwareKeyBytes(
                keyCode: key.keyCode,
                modifierFlags: key.modifierFlags,
                characters: key.charactersIgnoringModifiers
            ) {
                terminalView?.send(mapped)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

extension TerminalViewController: SSHTerminalDataSourceDelegate {
    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateTitle title: String) {
        onTitleChange?(title)
    }

    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateScrollPosition position: Double) {}

    func dataSource(_ dataSource: SSHTerminalDataSource, didRequestOpenLink link: String) {}
}
