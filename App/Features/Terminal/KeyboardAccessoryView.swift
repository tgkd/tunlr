import UIKit
import SwiftTerm

struct KeyMapping: Sendable {
    static func applyCtrl(to character: UInt8) -> UInt8 {
        switch character {
        case 0x61...0x7a: return character - 0x60
        case 0x41...0x5a: return character - 0x40
        case 0x40: return 0x00
        case 0x5b: return 0x1b
        case 0x5c: return 0x1c
        case 0x5d: return 0x1d
        case 0x5e: return 0x1e
        case 0x5f: return 0x1f
        default: return character
        }
    }

    static func hardwareKeyBytes(
        keyCode: UIKeyboardHIDUsage,
        modifierFlags: UIKeyModifierFlags,
        characters: String?
    ) -> [UInt8]? {
        if modifierFlags.contains(.command), let chars = characters, !chars.isEmpty {
            return [0x1b] + Array(chars.utf8)
        }
        return nil
    }
}

// MARK: - Panel Model

struct ToolbarPanel: Sendable {
    let id: String
    let title: String
    let icon: String
    let items: [ToolbarItem]

    enum ToolbarItem: Sendable {
        case toolbarButton(ToolbarButtonKind)
        case shortcut(Shortcut)

        var label: String {
            switch self {
            case .toolbarButton(let kind): return kind.displayTitle
            case .shortcut(let s): return s.shortcutDisplay.isEmpty ? s.label : s.shortcutDisplay
            }
        }

        var bytes: [UInt8]? {
            switch self {
            case .toolbarButton(let kind): return kind.bytes
            case .shortcut(let s): return s.bytes
            }
        }

        var isModifier: Bool {
            switch self {
            case .toolbarButton(let kind): return kind.isModifier
            case .shortcut: return false
            }
        }
    }
}

// MARK: - Accessory View

@MainActor
final class SimpleTerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?
    var onMicrophoneTapped: (() -> Void)?

    var showMicButton: Bool = false {
        didSet {
            guard oldValue != showMicButton else { return }
            rebuildFixedTrailing()
            layoutSubviews()
        }
    }

    var panels: [ToolbarPanel] = [] {
        didSet { rebuildAll() }
    }

    private var selectedPanelIndex: Int = 0
    private var panelPickerButton = UIButton(type: .system)
    private var scrollView = UIScrollView()
    private var actionButtons: [UIButton] = []
    private var actionItems: [UIButton: ToolbarPanel.ToolbarItem] = [:]
    private var ctrlButton: UIButton?
    private var micButton: UIButton?
    private var trailingButtons: [UIButton] = []

    var controlModifier: Bool = false {
        didSet {
            ctrlButton?.isSelected = controlModifier
            ctrlButton?.backgroundColor = controlModifier ? UIView().tintColor : buttonColor
            terminalView?.controlModifier = controlModifier
        }
    }

    var isMicActive: Bool = false {
        didSet {
            micButton?.backgroundColor = isMicActive ? .systemRed : buttonColor
        }
    }

    var enableInputClicksWhenVisible: Bool { true }

    private var buttonColor: UIColor = UIColor(white: 0.22, alpha: 1)
    private var textColor: UIColor = .white
    private let pad: CGFloat = 4
    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    init(frame: CGRect, terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: frame, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupSubviews() {
        panelPickerButton.layer.masksToBounds = true
        panelPickerButton.backgroundColor = .systemBlue
        panelPickerButton.tintColor = .white
        panelPickerButton.showsMenuAsPrimaryAction = true
        addSubview(panelPickerButton)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        rebuildFixedTrailing()
    }

    private func rebuildFixedTrailing() {
        for btn in trailingButtons { btn.removeFromSuperview() }
        trailingButtons.removeAll()
        micButton = nil

        let iconSize: CGFloat = isIPad ? 18 : 14

        if showMicButton {
            let micBtn = makeButton(title: nil, action: #selector(micTapped))
            let cfg = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            micBtn.setImage(
                UIImage(systemName: "mic.fill", withConfiguration: cfg)?
                    .withTintColor(textColor, renderingMode: .alwaysOriginal),
                for: .normal
            )
            micButton = micBtn
            trailingButtons.append(micBtn)
            addSubview(micBtn)
        }

        let hideBtn = makeButton(title: nil, action: #selector(hideKeyboard))
        let cfg = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        hideBtn.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: cfg)?
                .withTintColor(textColor, renderingMode: .alwaysOriginal),
            for: .normal
        )
        trailingButtons.append(hideBtn)
        addSubview(hideBtn)
    }

    private func rebuildAll() {
        if selectedPanelIndex >= panels.count {
            selectedPanelIndex = 0
        }
        updatePanelPickerMenu()
        rebuildActionButtons()
    }

    private func updatePanelPickerMenu() {
        guard !panels.isEmpty else {
            panelPickerButton.setTitle("--", for: .normal)
            panelPickerButton.menu = nil
            return
        }

        let current = panels[selectedPanelIndex]
        let iconCfg = UIImage.SymbolConfiguration(pointSize: isIPad ? 18 : 14, weight: .medium)
        panelPickerButton.setImage(
            UIImage(systemName: current.icon, withConfiguration: iconCfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal),
            for: .normal
        )
        panelPickerButton.setTitle(nil, for: .normal)

        let actions = panels.enumerated().map { idx, panel in
            UIAction(
                title: panel.title,
                image: UIImage(systemName: panel.icon),
                state: idx == selectedPanelIndex ? .on : .off
            ) { [weak self] _ in
                self?.selectPanel(idx)
            }
        }
        panelPickerButton.menu = UIMenu(children: actions)
    }

    private func selectPanel(_ index: Int) {
        guard index < panels.count, index != selectedPanelIndex else { return }
        selectedPanelIndex = index
        updatePanelPickerMenu()
        rebuildActionButtons()
    }

    private func rebuildActionButtons() {
        for btn in actionButtons { btn.removeFromSuperview() }
        actionButtons.removeAll()
        actionItems.removeAll()
        ctrlButton = nil

        guard !panels.isEmpty else {
            setNeedsLayout()
            return
        }

        let items = panels[selectedPanelIndex].items
        for item in items {
            let btn = makeButton(title: item.label, action: #selector(actionButtonTapped(_:)))
            actionItems[btn] = item
            if case .toolbarButton(.ctrl) = item { ctrlButton = btn }
            actionButtons.append(btn)
            scrollView.addSubview(btn)
        }

        setNeedsLayout()
        scrollView.contentOffset = .zero
    }

    private func makeButton(title: String?, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = isIPad ? 7 : 5
        btn.layer.masksToBounds = true
        btn.backgroundColor = buttonColor
        if let title {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .monospacedSystemFont(ofSize: isIPad ? 16 : 13, weight: .medium)
            btn.titleLabel?.lineBreakMode = .byClipping
        }
        btn.setTitleColor(textColor, for: .normal)
        btn.tintColor = textColor
        btn.addTarget(self, action: action, for: .touchDown)
        return btn
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = frame.height - 8
        guard h > 0 else { return }

        let btnMinW: CGFloat = isIPad ? 52 : 44
        let trailingW: CGFloat = CGFloat(trailingButtons.count) * (btnMinW + pad)

        // Panel picker (circle)
        let pickerSize: CGFloat = min(h, isIPad ? 42 : 36)
        let pickerY = 4 + (h - pickerSize) / 2
        panelPickerButton.frame = CGRect(x: pad, y: pickerY, width: pickerSize, height: pickerSize)
        panelPickerButton.layer.cornerRadius = pickerSize / 2
        let pickerW = pickerSize
        panelPickerButton.isHidden = panels.count <= 1

        let scrollLeading = panels.count <= 1 ? pad : pad + pickerW + pad
        let scrollTrailing = frame.width - trailingW
        scrollView.frame = CGRect(x: scrollLeading, y: 0, width: scrollTrailing - scrollLeading, height: frame.height)

        // Action buttons inside scroll view — sized to fit content
        let buttonCount = actionButtons.count
        if buttonCount > 0 {
            let btnPadH: CGFloat = 12
            var x: CGFloat = 0
            for btn in actionButtons {
                let fitW = max(btn.intrinsicContentSize.width + btnPadH, btnMinW)
                btn.frame = CGRect(x: x, y: 4, width: fitW, height: h)
                x += fitW + pad
            }
            scrollView.contentSize = CGSize(width: x - pad, height: frame.height)
        } else {
            scrollView.contentSize = .zero
        }

        // Trailing fixed buttons
        var tx = frame.width - trailingW + pad
        for btn in trailingButtons {
            btn.frame = CGRect(x: tx, y: 4, width: btnMinW, height: h)
            tx += btnMinW + pad
        }
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        UIDevice.current.playInputClick()
        guard let item = actionItems[sender] else { return }
        if item.isModifier {
            controlModifier.toggle()
        } else if let bytes = item.bytes {
            terminalView?.send(bytes)
        }
    }

    @objc private func micTapped() {
        UIDevice.current.playInputClick()
        onMicrophoneTapped?()
    }

    @objc private func hideKeyboard() {
        UIDevice.current.playInputClick()
        terminalView?.resignFirstResponder()
    }

    func updateColors(buttonBg: UIColor, textColor newTextColor: UIColor) {
        buttonColor = buttonBg
        textColor = newTextColor

        panelPickerButton.backgroundColor = .systemBlue
        panelPickerButton.tintColor = .white
        if let img = panelPickerButton.image(for: .normal) {
            panelPickerButton.setImage(img.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        }

        let allBtns = actionButtons + trailingButtons
        for btn in allBtns {
            btn.backgroundColor = buttonBg
            btn.setTitleColor(newTextColor, for: .normal)
            btn.tintColor = newTextColor
            if let img = btn.image(for: .normal) {
                btn.setImage(img.withTintColor(newTextColor, renderingMode: .alwaysOriginal), for: .normal)
            }
        }
        if controlModifier {
            ctrlButton?.backgroundColor = UIView().tintColor
        }
        if isMicActive {
            micButton?.backgroundColor = .systemRed
        }
    }
}
