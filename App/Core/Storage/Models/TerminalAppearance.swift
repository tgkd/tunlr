import UIKit

struct TerminalAppearance: Codable, Sendable, Equatable {
    var fontName: TerminalFontName = .sfMono
    var fontSize: CGFloat = 14
    var themeName: TerminalThemeName = .defaultDark
    var cursorStyle: TerminalCursorStyle = .block
    var cursorBlink: Bool = true
    var scrollbackSize: ScrollbackSize = .lines5K
    var toolbarButtons: [ToolbarButtonKind] = [.esc, .ctrl, .tab]
    var enabledShortcutPacks: [ShortcutPackID] = [.shell]
    var favoriteShortcuts: [Shortcut] = []
    var customizedPacks: [ShortcutPackID: [Shortcut]] = [:]
    var eventNotifications: EventNotificationSettings = EventNotificationSettings()

    func shortcuts(for packID: ShortcutPackID) -> [Shortcut] {
        customizedPacks[packID] ?? ShortcutPackCatalog.shortcuts(for: packID)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try container.decodeIfPresent(TerminalFontName.self, forKey: .fontName) ?? .sfMono
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 14
        themeName = try container.decodeIfPresent(TerminalThemeName.self, forKey: .themeName) ?? .defaultDark
        cursorStyle = try container.decodeIfPresent(TerminalCursorStyle.self, forKey: .cursorStyle) ?? .block
        cursorBlink = try container.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? true
        scrollbackSize = try container.decodeIfPresent(ScrollbackSize.self, forKey: .scrollbackSize) ?? .lines5K
        toolbarButtons = try container.decodeIfPresent([ToolbarButtonKind].self, forKey: .toolbarButtons) ?? [.esc, .ctrl, .tab]
        enabledShortcutPacks = try container.decodeIfPresent([ShortcutPackID].self, forKey: .enabledShortcutPacks) ?? [.shell]
        favoriteShortcuts = try container.decodeIfPresent([Shortcut].self, forKey: .favoriteShortcuts) ?? []
        customizedPacks = try container.decodeIfPresent([ShortcutPackID: [Shortcut]].self, forKey: .customizedPacks) ?? [:]
        eventNotifications = try container.decodeIfPresent(EventNotificationSettings.self, forKey: .eventNotifications) ?? EventNotificationSettings()
    }
}

enum TerminalCursorStyle: String, Codable, Sendable, CaseIterable {
    case block
    case underline
    case bar

    var displayName: String {
        switch self {
        case .block: return "Block"
        case .underline: return "Underline"
        case .bar: return "Bar"
        }
    }
}

enum ScrollbackSize: Int, Codable, Sendable, CaseIterable {
    case lines1K = 1000
    case lines5K = 5000
    case lines10K = 10000
    case lines50K = 50000

    var displayName: String {
        switch self {
        case .lines1K: return "1K"
        case .lines5K: return "5K"
        case .lines10K: return "10K"
        case .lines50K: return "50K"
        }
    }
}

enum TerminalFontName: String, Codable, Sendable, CaseIterable {
    case sfMono
    case firaCode
    case jetBrainsMono
    case sourceCodePro

    var displayName: String {
        switch self {
        case .sfMono: return "SF Mono"
        case .firaCode: return "Fira Code"
        case .jetBrainsMono: return "JetBrains Mono"
        case .sourceCodePro: return "Source Code Pro"
        }
    }

    var postScriptName: String? {
        switch self {
        case .sfMono: return nil
        case .firaCode: return "FiraCode-Regular"
        case .jetBrainsMono: return "JetBrainsMono-Regular"
        case .sourceCodePro: return "SourceCodePro-Regular"
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        if let ps = postScriptName, let font = UIFont(name: ps, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

enum TerminalThemeName: String, Codable, Sendable, CaseIterable {
    case defaultDark
    case solarizedDark
    case solarizedLight
    case dracula
    case nord
    case monokai
    case oneDark
    case githubLight
    case gruvboxLight
    case catppuccinMocha
    case tokyoNight
    case rosePine
    case synthwave
    case kanagawa
}
