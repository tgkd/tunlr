import Foundation

struct Shortcut: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(label)-\(shortcutDisplay)" }
    let label: String
    let shortcutDisplay: String
    let icon: String
    let bytes: [UInt8]
}

enum ShortcutPackID: String, Codable, Sendable, CaseIterable, Identifiable {
    case favorites
    case shell
    case tmux
    case vim
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .favorites: return "Favorites"
        case .shell: return "Shell"
        case .tmux: return "Tmux"
        case .vim: return "Vim"
        case .claudeCode: return "Claude"
        }
    }

    var icon: String {
        switch self {
        case .favorites: return "star"
        case .shell: return "terminal"
        case .tmux: return "rectangle.split.2x1"
        case .vim: return "character.cursor.ibeam"
        case .claudeCode: return "sparkles"
        }
    }
}
