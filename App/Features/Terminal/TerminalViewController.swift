import UIKit
import SwiftTerm

@MainActor
final class TerminalViewController: UIViewController {
    private(set) var terminalView: TerminalView!
    private(set) var dataSource: SSHTerminalDataSource

    var onTitleChange: ((String) -> Void)?
    var onSizeChange: ((Int, Int) -> Void)?
    var onMicrophoneTapped: (() -> Void)?
    var onTerminalEvent: ((TerminalEvent) -> Void)?
    var voiceInputEnabled: Bool = false {
        didSet {
            if let accessory = terminalView?.inputAccessoryView as? SimpleTerminalAccessory {
                accessory.showMicButton = voiceInputEnabled
            }
        }
    }

    private var currentAppearance: TerminalAppearance?
    private var terminalBottomConstraint: NSLayoutConstraint!
    private var keyboardOverlap: CGFloat = 0

    init(dataSource: SSHTerminalDataSource) {
        self.dataSource = dataSource
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        terminalBottomConstraint = terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: hPadding),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -hPadding),
            terminalBottomConstraint,
        ])

        let accessoryHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 52 : 44
        let accessory = SimpleTerminalAccessory(
            frame: CGRect(x: 0, y: 0, width: view.frame.width, height: accessoryHeight),
            terminalView: terminalView
        )
        accessory.onMicrophoneTapped = { [weak self] in
            self?.onMicrophoneTapped?()
        }
        terminalView.inputAccessoryView = accessory

        dataSource.attachTerminalView(terminalView)
        dataSource.delegate = self

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyBottomInset()
        notifyTerminalSize()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyBottomInset()
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        updateKeyboardOverlap(from: notification, hiding: false)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        updateKeyboardOverlap(from: notification, hiding: true)
    }

    private func updateKeyboardOverlap(from notification: Notification, hiding: Bool) {
        guard let userInfo = notification.userInfo,
              let endValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }

        let endFrameInWindow = endValue.cgRectValue
        let endFrameInView = view.convert(endFrameInWindow, from: nil)
        let overlap = hiding ? 0 : max(0, view.bounds.maxY - endFrameInView.minY)
        guard overlap != keyboardOverlap else { return }
        keyboardOverlap = overlap

        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        applyBottomInset()
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    private func applyBottomInset() {
        let safeBottom = view.safeAreaInsets.bottom
        let inset = max(safeBottom, keyboardOverlap)
        if terminalBottomConstraint.constant != -inset {
            terminalBottomConstraint.constant = -inset
        }
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

        let swiftTermCursorStyle: SwiftTerm.CursorStyle = {
            switch (appearance.cursorStyle, appearance.cursorBlink) {
            case (.block, true): return .blinkBlock
            case (.block, false): return .steadyBlock
            case (.underline, true): return .blinkUnderline
            case (.underline, false): return .steadyUnderline
            case (.bar, true): return .blinkBar
            case (.bar, false): return .steadyBar
            }
        }()
        terminalView.getTerminal().setCursorStyle(swiftTermCursorStyle)
        terminalView.getTerminal().changeHistorySize(appearance.scrollbackSize.rawValue)

        terminalView.selectedTextBackgroundColor = theme.isDark
            ? UIColor(white: 0.3, alpha: 0.6)
            : UIColor(white: 0.7, alpha: 0.6)

        let wantsMetal = appearance.useMetalRenderer
        let hadMetal = terminalView.isUsingMetalRenderer
        if wantsMetal != hadMetal {
            try? terminalView.setUseMetal(wantsMetal)
        }
        if wantsMetal {
            let mode: MetalBufferingMode = appearance.metalBufferingMode == .perFrame
                ? .perFrameAggregated : .perRowPersistent
            terminalView.metalBufferingMode = mode
        }

        if let accessory = terminalView.inputAccessoryView as? SimpleTerminalAccessory {
            let btnBg = theme.isDark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.88, alpha: 1)
            let txtColor: UIColor = theme.isDark ? .white : .black
            accessory.updateColors(buttonBg: btnBg, textColor: txtColor)
            accessory.panels = Self.buildPanels(from: appearance)
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

    static func buildPanels(from appearance: TerminalAppearance) -> [ToolbarPanel] {
        var panels: [ToolbarPanel] = []

        let customItems = appearance.toolbarButtons.map { ToolbarPanel.ToolbarItem.toolbarButton($0) }
        panels.append(ToolbarPanel(id: "custom", title: "Keys", icon: "keyboard", items: customItems))

        if !appearance.favoriteShortcuts.isEmpty {
            let favItems = appearance.favoriteShortcuts.map { ToolbarPanel.ToolbarItem.shortcut($0) }
            panels.append(ToolbarPanel(id: "favorites", title: "Favs", icon: "star", items: favItems))
        }

        for packID in appearance.enabledShortcutPacks where packID != .favorites {
            let shortcuts = appearance.shortcuts(for: packID)
            let items = shortcuts.map { ToolbarPanel.ToolbarItem.shortcut($0) }
            panels.append(ToolbarPanel(id: packID.rawValue, title: packID.displayName, icon: packID.icon, items: items))
        }

        return panels
    }
}

extension TerminalViewController: SSHTerminalDataSourceDelegate {
    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateTitle title: String) {
        onTitleChange?(title)
    }

    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateScrollPosition position: Double) {}

    func dataSource(_ dataSource: SSHTerminalDataSource, didRequestOpenLink link: String) {}

    func dataSource(_ dataSource: SSHTerminalDataSource, didEmitEvent event: TerminalEvent) {
        onTerminalEvent?(event)
    }
}
