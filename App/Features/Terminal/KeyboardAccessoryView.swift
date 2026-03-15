import UIKit
import SwiftTerm

struct KeyMapping: Sendable {
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
        if modifierFlags.contains(.command), let chars = characters, !chars.isEmpty {
            return [0x1b] + Array(chars.utf8)
        }
        return nil
    }
}

@MainActor
final class SimpleTerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?
    var onMicrophoneTapped: (() -> Void)?
    var showMicButton: Bool = false {
        didSet {
            guard oldValue != showMicButton else { return }
            rebuildButtons()
        }
    }

    private var ctrlButton: UIButton?
    private var micButton: UIButton?
    private var buttons: [UIButton] = []

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

    init(frame: CGRect, terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: frame, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupButtons() {
        rebuildButtons()
    }

    private func rebuildButtons() {
        for btn in buttons { btn.removeFromSuperview() }
        buttons.removeAll()
        ctrlButton = nil
        micButton = nil

        let keys: [(String, Selector)] = [
            ("Esc", #selector(escTapped)),
            ("Ctrl", #selector(ctrlTapped)),
            ("Tab", #selector(tabTapped)),
        ]

        for (title, action) in keys {
            let btn = makeButton(title: title, action: action)
            if title == "Ctrl" { ctrlButton = btn }
            buttons.append(btn)
            addSubview(btn)
        }

        if showMicButton {
            let micBtn = makeButton(title: nil, action: #selector(micTapped))
            let micConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            micBtn.setImage(
                UIImage(systemName: "mic.fill", withConfiguration: micConfig)?
                    .withTintColor(textColor, renderingMode: .alwaysOriginal),
                for: .normal
            )
            micButton = micBtn
            buttons.append(micBtn)
            addSubview(micBtn)
        }

        let hideBtn = makeButton(title: nil, action: #selector(hideKeyboard))
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        hideBtn.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config)?
                .withTintColor(textColor, renderingMode: .alwaysOriginal),
            for: .normal
        )
        buttons.append(hideBtn)
        addSubview(hideBtn)

        setNeedsLayout()
    }

    private func makeButton(title: String?, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 5
        btn.layer.masksToBounds = true
        btn.backgroundColor = buttonColor
        if let title {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        }
        btn.setTitleColor(textColor, for: .normal)
        btn.tintColor = textColor
        btn.addTarget(self, action: action, for: .touchDown)
        return btn
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 4
        let h = frame.height - 8
        guard h > 0, !buttons.isEmpty else { return }

        let totalPad = pad * CGFloat(buttons.count + 1)
        let w = (frame.width - totalPad) / CGFloat(buttons.count)

        var x = pad
        for btn in buttons {
            btn.frame = CGRect(x: x, y: 4, width: w, height: h)
            x += w + pad
        }
    }

    @objc private func escTapped() {
        UIDevice.current.playInputClick()
        terminalView?.send([0x1b])
    }

    @objc private func ctrlTapped() {
        UIDevice.current.playInputClick()
        controlModifier.toggle()
    }

    @objc private func tabTapped() {
        UIDevice.current.playInputClick()
        terminalView?.send([0x09])
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
        for btn in buttons {
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
