import UIKit
import SwiftTerm

@MainActor
final class TerminalViewController: UIViewController {
    private(set) var terminalView: TerminalView!
    private(set) var dataSource: SSHTerminalDataSource

    var onTitleChange: ((String) -> Void)?
    var onSizeChange: ((Int, Int) -> Void)?
    var onMicrophoneTapped: (() -> Void)?
    var voiceInputEnabled: Bool = false {
        didSet {
            if let accessory = terminalView?.inputAccessoryView as? SimpleTerminalAccessory {
                accessory.showMicButton = voiceInputEnabled
            }
        }
    }

    private var currentAppearance: TerminalAppearance?

    init(dataSource: SSHTerminalDataSource) {
        self.dataSource = dataSource
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        terminalView = TerminalView(frame: .zero, font: nil)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)

        let hPadding: CGFloat = 12
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: hPadding),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -hPadding),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let accessory = SimpleTerminalAccessory(
            frame: CGRect(x: 0, y: 0, width: view.frame.width, height: 44),
            terminalView: terminalView
        )
        accessory.onMicrophoneTapped = { [weak self] in
            self?.onMicrophoneTapped?()
        }
        terminalView.inputAccessoryView = accessory

        dataSource.attachTerminalView(terminalView)
        dataSource.delegate = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        notifyTerminalSize()
    }

    func applyAppearance(_ appearance: TerminalAppearance) {
        guard appearance != currentAppearance else { return }
        currentAppearance = appearance

        let font = appearance.fontName.uiFont(size: appearance.fontSize)
        terminalView.font = font

        let theme = TerminalThemeCatalog.theme(for: appearance.themeName)
        terminalView.nativeBackgroundColor = theme.backgroundColor.uiColor
        terminalView.nativeForegroundColor = theme.foregroundColor.uiColor
        view.backgroundColor = theme.backgroundColor.uiColor

        let ansiColors = theme.ansiColors.map { $0.swiftTermColor }
        terminalView.installColors(ansiColors)

        if let accessory = terminalView.inputAccessoryView as? SimpleTerminalAccessory {
            let btnBg = theme.isDark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.88, alpha: 1)
            let txtColor: UIColor = theme.isDark ? .white : .black
            accessory.updateColors(buttonBg: btnBg, textColor: txtColor)
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

    func sendText(_ text: String) {
        terminalView?.send(Array(text.utf8))
    }

    func setMicActive(_ active: Bool) {
        if let accessory = terminalView?.inputAccessoryView as? SimpleTerminalAccessory {
            accessory.isMicActive = active
        }
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
