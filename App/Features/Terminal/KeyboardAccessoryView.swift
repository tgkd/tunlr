import UIKit
import SwiftTerm

enum AccessoryKey: String, CaseIterable, Sendable {
    case esc
    case tab
    case ctrl
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case pipe
    case tilde
    case slash
}

struct KeyMapping: Sendable {
    static func bytes(for key: AccessoryKey) -> [UInt8]? {
        switch key {
        case .esc:
            return [0x1b]
        case .tab:
            return [0x09]
        case .ctrl:
            return nil
        case .arrowUp:
            return EscapeSequences.moveUpNormal
        case .arrowDown:
            return EscapeSequences.moveDownNormal
        case .arrowLeft:
            return EscapeSequences.moveLeftNormal
        case .arrowRight:
            return EscapeSequences.moveRightNormal
        case .pipe:
            return Array("|".utf8)
        case .tilde:
            return Array("~".utf8)
        case .slash:
            return Array("/".utf8)
        }
    }

    static func applyCtrl(to character: UInt8) -> UInt8 {
        switch character {
        case 0x61...0x7a: // a-z
            return character - 0x60
        case 0x41...0x5a: // A-Z
            return character - 0x40
        case 0x40: // @
            return 0x00
        case 0x5b: // [
            return 0x1b
        case 0x5c: // backslash
            return 0x1c
        case 0x5d: // ]
            return 0x1d
        case 0x5e: // ^
            return 0x1e
        case 0x5f: // _
            return 0x1f
        default:
            return character
        }
    }

    static func hardwareKeyBytes(
        keyCode: UIKeyboardHIDUsage,
        modifierFlags: UIKeyModifierFlags,
        characters: String?
    ) -> [UInt8]? {
        // Cmd as Meta: prefix with ESC
        if modifierFlags.contains(.command), let chars = characters, !chars.isEmpty {
            return [0x1b] + Array(chars.utf8)
        }
        // Fn+arrows -> Page Up/Down (handled natively by iOS, but we add explicit support)
        // Note: Fn+Up/Down naturally sends PageUp/PageDown on iOS hardware keyboards
        return nil
    }
}

@MainActor
final class KeyboardAccessoryView: UIView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?

    private(set) var isCtrlLocked: Bool = false {
        didSet {
            ctrlButton?.isSelected = isCtrlLocked
            terminalView?.controlModifier = isCtrlLocked
        }
    }

    private var ctrlButton: UIButton?
    private var buttons: [UIView] = []
    private var repeatTimer: Timer?
    private var repeatTask: Task<Void, Never>?

    var enableInputClicksWhenVisible: Bool { true }

    private let contentHeight: CGFloat

    init(frame: CGRect, terminalView: TerminalView) {
        self.terminalView = terminalView
        self.contentHeight = frame.height
        super.init(frame: frame)
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear
        setupButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    private func setupButtons() {
        for button in buttons {
            button.removeFromSuperview()
        }
        buttons.removeAll()

        let leftKeys: [(String, AccessoryKey, String?)] = [
            ("esc", .esc, "escape"),
            ("ctrl", .ctrl, "control"),
            ("tab", .tab, "arrow.right.to.line.compact"),
        ]

        let middleKeys: [(String, AccessoryKey, String?)] = [
            ("~", .tilde, nil),
            ("|", .pipe, nil),
            ("/", .slash, nil),
        ]

        let arrowKeys: [(String, AccessoryKey, String?)] = [
            ("", .arrowLeft, "arrow.left"),
            ("", .arrowDown, "arrow.down"),
            ("", .arrowUp, "arrow.up"),
            ("", .arrowRight, "arrow.right"),
        ]

        for (title, key, icon) in leftKeys {
            let button = makeButton(title: title, key: key, icon: icon, isDark: true)
            if key == .ctrl {
                ctrlButton = button
            }
            buttons.append(button)
        }

        for (title, key, icon) in middleKeys {
            let button = makeButton(title: title, key: key, icon: icon, isDark: false)
            buttons.append(button)
        }

        for (title, key, icon) in arrowKeys {
            let button = makeAutoRepeatButton(title: title, key: key, icon: icon)
            buttons.append(button)
        }

        for button in buttons {
            addSubview(button)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding: CGFloat = 4
        let buttonHeight = contentHeight - 8
        guard buttonHeight > 0 else { return }
        let totalPadding = padding * CGFloat(buttons.count + 1)
        let buttonWidth = (frame.width - totalPadding) / CGFloat(buttons.count)

        var x: CGFloat = padding
        for button in buttons {
            button.frame = CGRect(x: x, y: 4, width: buttonWidth, height: buttonHeight)
            x += buttonWidth + padding
        }
    }

    private func makeButton(title: String, key: AccessoryKey, icon: String?, isDark: Bool) -> UIButton {
        let button = HighlightButton(type: .system)
        button.tag = AccessoryKey.allCases.firstIndex(of: key)!
        button.layer.cornerRadius = 6
        button.layer.masksToBounds = true
        styleButton(button, isDark: isDark)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let icon, let image = UIImage(systemName: icon, withConfiguration: symbolConfig) {
            button.setImage(image, for: .normal)
            button.tintColor = buttonTextColor
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        }

        if key == .ctrl {
            button.addTarget(self, action: #selector(ctrlTapped), for: .touchUpInside)
        } else {
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchDown)
        }

        return button
    }

    private func makeAutoRepeatButton(title: String, key: AccessoryKey, icon: String?) -> UIButton {
        let button = makeButton(title: title, key: key, icon: icon, isDark: false)
        button.removeTarget(self, action: #selector(keyTapped(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(arrowDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(cancelRepeat), for: .touchUpInside)
        button.addTarget(self, action: #selector(cancelRepeat), for: .touchUpOutside)
        button.addTarget(self, action: #selector(cancelRepeat), for: .touchCancel)
        return button
    }

    @objc private func keyTapped(_ sender: UIButton) {
        let key = AccessoryKey.allCases[sender.tag]
        UIDevice.current.playInputClick()
        if let data = KeyMapping.bytes(for: key) {
            terminalView?.send(data)
        }
    }

    @objc private func ctrlTapped() {
        UIDevice.current.playInputClick()
        isCtrlLocked.toggle()
    }

    @objc private func arrowDown(_ sender: UIButton) {
        let key = AccessoryKey.allCases[sender.tag]
        guard let data = KeyMapping.bytes(for: key) else { return }
        UIDevice.current.playInputClick()
        terminalView?.send(data)

        let tv = terminalView
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    tv?.send(data)
                }
            }
        }
    }

    @objc private func cancelRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    private var themeDark: Bool = true

    func updateTheme(isDark: Bool, backgroundColor: UIColor) {
        themeDark = isDark
        self.backgroundColor = .clear
        for (index, button) in buttons.enumerated() {
            guard let btn = button as? UIButton else { continue }
            let isLeftSection = index < 3
            styleButton(btn, isDark: isLeftSection)
        }
    }

    private var buttonTextColor: UIColor {
        themeDark ? .white : .black
    }

    private func styleButton(_ button: UIButton, isDark: Bool) {
        if themeDark {
            button.backgroundColor = isDark
                ? UIColor(white: 0.3, alpha: 1)
                : UIColor(white: 0.22, alpha: 1)
        } else {
            button.backgroundColor = isDark
                ? UIColor(white: 0.78, alpha: 1)
                : UIColor(white: 0.92, alpha: 1)
        }
        button.tintColor = buttonTextColor
        button.setTitleColor(buttonTextColor, for: .normal)
    }
}

private final class HighlightButton: UIButton {
    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? tintColor : backgroundColor
        }
    }
}
