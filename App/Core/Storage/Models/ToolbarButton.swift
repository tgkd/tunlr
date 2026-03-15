import Foundation

enum ToolbarButtonKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case esc
    case ctrl
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case enter
    case pipe
    case dash
    case tilde
    case slash

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .esc: return "Esc"
        case .ctrl: return "Ctrl"
        case .tab: return "Tab"
        case .arrowUp: return "\u{2191}"
        case .arrowDown: return "\u{2193}"
        case .arrowLeft: return "\u{2190}"
        case .arrowRight: return "\u{2192}"
        case .enter: return "\u{23CE}"
        case .pipe: return "|"
        case .dash: return "-"
        case .tilde: return "~"
        case .slash: return "/"
        }
    }

    var settingsLabel: String {
        switch self {
        case .esc: return "Esc"
        case .ctrl: return "Ctrl"
        case .tab: return "Tab"
        case .arrowUp: return "Arrow Up"
        case .arrowDown: return "Arrow Down"
        case .arrowLeft: return "Arrow Left"
        case .arrowRight: return "Arrow Right"
        case .enter: return "Enter"
        case .pipe: return "Pipe |"
        case .dash: return "Dash -"
        case .tilde: return "Tilde ~"
        case .slash: return "Slash /"
        }
    }

    var bytes: [UInt8]? {
        switch self {
        case .esc: return [0x1b]
        case .ctrl: return nil
        case .tab: return [0x09]
        case .arrowUp: return [0x1b, 0x5b, 0x41]
        case .arrowDown: return [0x1b, 0x5b, 0x42]
        case .arrowRight: return [0x1b, 0x5b, 0x43]
        case .arrowLeft: return [0x1b, 0x5b, 0x44]
        case .enter: return [0x0d]
        case .pipe: return [0x7c]
        case .dash: return [0x2d]
        case .tilde: return [0x7e]
        case .slash: return [0x2f]
        }
    }

    var isModifier: Bool { self == .ctrl }
}
