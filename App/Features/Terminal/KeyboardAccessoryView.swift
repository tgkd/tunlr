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

        var isRepeatable: Bool {
            switch self {
            case .toolbarButton(let kind): return kind.isRepeatable
            case .shortcut: return false
            }
        }
    }
}

// MARK: - Accessory View

enum ModifierLatch: Sendable {
    case off
    case oneShot
    case locked

    var isActive: Bool { self != .off }

    var next: ModifierLatch {
        switch self {
        case .off: return .oneShot
        case .oneShot: return .locked
        case .locked: return .off
        }
    }
}

@MainActor
final class SimpleTerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?
    var onMicrophoneTapped: (() -> Void)?

    var size: ToolbarSize = .regular {
        didSet {
            guard oldValue != size else { return }
            rebuildAll()
            rebuildFixedTrailing()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var showMicButton: Bool = false {
        didSet {
            guard oldValue != showMicButton else { return }
            rebuildFixedTrailing()
            setNeedsLayout()
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
    private var altButton: UIButton?
    private var micButton: UIButton?
    private var trailingButtons: [UIButton] = []
    private var repeatTask: Task<Void, Never>?

    var controlLatch: ModifierLatch = .off {
        didSet {
            applyLatchStyle(to: ctrlButton, latch: controlLatch)
            terminalView?.controlModifier = controlLatch.isActive
            if controlLatch.isActive, metaLatch.isActive { metaLatch = .off }
        }
    }

    var metaLatch: ModifierLatch = .off {
        didSet {
            applyLatchStyle(to: altButton, latch: metaLatch)
            terminalView?.metaModifier = metaLatch.isActive
            if metaLatch.isActive, controlLatch.isActive { controlLatch = .off }
        }
    }

    var isMicActive: Bool = false {
        didSet { applyMicStyle() }
    }

    var enableInputClicksWhenVisible: Bool { true }

    private var textColor: UIColor = .label
    private let gap: CGFloat = 6
    private let sidePadding: CGFloat = 6
    private var isPad: Bool { traitCollection.userInterfaceIdiom == .pad }
    private var keyHeight: CGFloat { size.keyHeight(isPad: isPad) }
    private var glyphTarget: CGFloat { size.glyphTarget(isPad: isPad) }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: size.rowHeight(isPad: isPad))
    }

    override func sizeThatFits(_ proposed: CGSize) -> CGSize {
        CGSize(width: proposed.width, height: size.rowHeight(isPad: isPad))
    }

    init(frame: CGRect, terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: frame, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupSubviews()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controlModifierWasReset(_:)),
            name: .terminalViewControlModifierReset,
            object: terminalView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metaModifierWasReset(_:)),
            name: .terminalViewMetaModifierReset,
            object: terminalView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupSubviews() {
        panelPickerButton.configuration = glyphConfiguration(image: nil, tint: .systemBlue)
        panelPickerButton.showsMenuAsPrimaryAction = true
        addSubview(panelPickerButton)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        rebuildFixedTrailing()
    }

    private func glyphConfiguration(image: UIImage?, tint: UIColor) -> UIButton.Configuration {
        var cfg = UIButton.Configuration.plain()
        cfg.image = image
        cfg.baseForegroundColor = tint
        cfg.contentInsets = .zero
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: size.glyphPointSize(isPad: isPad),
            weight: .regular
        )
        return cfg
    }

    private func keyConfiguration(title: String, background: UIColor?) -> UIButton.Configuration {
        var cfg = UIButton.Configuration.gray()
        cfg.baseForegroundColor = textColor
        cfg.baseBackgroundColor = background
        cfg.cornerStyle = .fixed
        cfg.background.cornerRadius = size.keyCornerRadius(isPad: isPad)
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15)
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: size.keyFontSize(isPad: isPad), weight: .regular)
        cfg.attributedTitle = AttributedString(title, attributes: attributes)
        return cfg
    }

    private func rebuildFixedTrailing() {
        for btn in trailingButtons { btn.removeFromSuperview() }
        trailingButtons.removeAll()
        micButton = nil

        if showMicButton {
            let micBtn = UIButton(type: .system)
            micBtn.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
            micButton = micBtn
            trailingButtons.append(micBtn)
            addSubview(micBtn)
            applyMicStyle()
        }

        let hideBtn = UIButton(type: .system)
        hideBtn.configuration = glyphConfiguration(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            tint: textColor
        )
        hideBtn.addTarget(self, action: #selector(hideKeyboard), for: .touchUpInside)
        trailingButtons.append(hideBtn)
        addSubview(hideBtn)
    }

    private func applyMicStyle() {
        micButton?.configuration = glyphConfiguration(
            image: UIImage(systemName: isMicActive ? "mic.fill" : "mic"),
            tint: isMicActive ? .systemRed : textColor
        )
    }

    private func applyLatchStyle(to button: UIButton?, latch: ModifierLatch) {
        guard let button, let title = button.configuration?.title
            ?? button.configuration?.attributedTitle.map({ String($0.characters) }) else { return }
        button.isSelected = latch.isActive
        let background: UIColor? = switch latch {
        case .off: nil
        case .oneShot: UIColor.tintColor.withAlphaComponent(0.45)
        case .locked: UIColor.tintColor
        }
        button.configuration = keyConfiguration(title: title, background: background)
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
            panelPickerButton.configuration = glyphConfiguration(image: nil, tint: .systemBlue)
            panelPickerButton.menu = nil
            return
        }

        let current = panels[selectedPanelIndex]
        panelPickerButton.configuration = glyphConfiguration(
            image: UIImage(systemName: current.icon),
            tint: .systemBlue
        )

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
        cancelRepeat()
        for btn in actionButtons { btn.removeFromSuperview() }
        actionButtons.removeAll()
        actionItems.removeAll()
        ctrlButton = nil
        altButton = nil

        guard !panels.isEmpty else {
            setNeedsLayout()
            return
        }

        for item in panels[selectedPanelIndex].items {
            let btn = makeKeyCap(title: item.label)
            actionItems[btn] = item
            if case .toolbarButton(.ctrl) = item { ctrlButton = btn }
            if case .toolbarButton(.alt) = item { altButton = btn }
            actionButtons.append(btn)
            scrollView.addSubview(btn)
        }

        applyLatchStyle(to: ctrlButton, latch: controlLatch)
        applyLatchStyle(to: altButton, latch: metaLatch)

        setNeedsLayout()
        scrollView.contentOffset = .zero
    }

    private func makeKeyCap(title: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.configuration = keyConfiguration(title: title, background: nil)
        btn.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchDown)
        btn.addTarget(
            self,
            action: #selector(actionButtonReleased),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        return btn
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let capHeight = min(keyHeight, frame.height - 4)
        guard capHeight > 0 else { return }

        let capY = (frame.height - capHeight) / 2
        let glyphY = (frame.height - glyphTarget) / 2
        let trailingWidth = CGFloat(trailingButtons.count) * (glyphTarget + gap)

        panelPickerButton.frame = CGRect(x: sidePadding, y: glyphY, width: glyphTarget, height: glyphTarget)
        panelPickerButton.isHidden = panels.count <= 1

        let scrollLeading = panels.count <= 1 ? sidePadding : sidePadding + glyphTarget + gap
        let scrollTrailing = frame.width - trailingWidth - sidePadding
        scrollView.frame = CGRect(
            x: scrollLeading,
            y: 0,
            width: max(0, scrollTrailing - scrollLeading),
            height: frame.height
        )

        if actionButtons.isEmpty {
            scrollView.contentSize = .zero
        } else {
            var x: CGFloat = 0
            for btn in actionButtons {
                let width = max(btn.intrinsicContentSize.width, glyphTarget)
                btn.frame = CGRect(x: x, y: capY, width: width, height: capHeight)
                x += width + gap
            }
            scrollView.contentSize = CGSize(width: x - gap, height: frame.height)
        }

        var tx = frame.width - trailingWidth
        for btn in trailingButtons {
            btn.frame = CGRect(x: tx, y: glyphY, width: glyphTarget, height: glyphTarget)
            tx += glyphTarget + gap
        }
    }

    @objc private func controlModifierWasReset(_ notification: Notification) {
        switch controlLatch {
        case .locked: terminalView?.controlModifier = true
        case .oneShot: controlLatch = .off
        case .off: break
        }
    }

    @objc private func metaModifierWasReset(_ notification: Notification) {
        switch metaLatch {
        case .locked: terminalView?.metaModifier = true
        case .oneShot: metaLatch = .off
        case .off: break
        }
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        UIDevice.current.playInputClick()
        guard let item = actionItems[sender] else { return }
        if case .toolbarButton(.ctrl) = item {
            controlLatch = controlLatch.next
        } else if case .toolbarButton(.alt) = item {
            metaLatch = metaLatch.next
        } else if let bytes = item.bytes {
            terminalView?.send(bytes)
            if item.isRepeatable {
                startRepeat(bytes: bytes)
            }
        }
    }

    @objc private func actionButtonReleased() {
        cancelRepeat()
    }

    private func startRepeat(bytes: [UInt8]) {
        cancelRepeat()
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                guard let self else { return }
                self.terminalView?.send(bytes)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func cancelRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    @objc private func micTapped() {
        UIDevice.current.playInputClick()
        onMicrophoneTapped?()
    }

    @objc private func hideKeyboard() {
        UIDevice.current.playInputClick()
        _ = terminalView?.resignFirstResponder()
    }

    func updateColors(textColor newTextColor: UIColor) {
        textColor = newTextColor

        for btn in actionButtons {
            guard let title = btn.configuration?.attributedTitle.map({ String($0.characters) }) else { continue }
            btn.configuration = keyConfiguration(title: title, background: nil)
        }
        applyLatchStyle(to: ctrlButton, latch: controlLatch)
        applyLatchStyle(to: altButton, latch: metaLatch)

        updatePanelPickerMenu()
        applyMicStyle()
        if let hideBtn = trailingButtons.last {
            hideBtn.configuration = glyphConfiguration(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                tint: newTextColor
            )
        }
    }
}
