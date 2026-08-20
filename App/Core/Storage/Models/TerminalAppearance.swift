import UIKit

struct TerminalAppearance: Codable, Sendable, Equatable {
    var fontName: TerminalFontName = .sfMono
    var fontSize: CGFloat = 14
    var themeName: TerminalThemeName = .defaultDark
    var cursorStyle: TerminalCursorStyle = .block
    var cursorBlink: Bool = true
    var scrollbackSize: ScrollbackSize = .lines5K
    var toolbarButtons: [ToolbarButtonKind] = [.esc, .ctrl, .tab]
    var toolbarSize: ToolbarSize = .regular
    var enabledShortcutPacks: [ShortcutPackID] = [.shell]
    var favoriteShortcuts: [Shortcut] = []
    var customizedPacks: [ShortcutPackID: [Shortcut]] = [:]
    var eventNotifications: EventNotificationSettings = EventNotificationSettings()
    var useMetalRenderer: Bool = false
    var metalBufferingMode: TerminalMetalBuffering = .perRow
    var preventDeviceSleepWhileConnected: Bool = false
    var allowRemoteClipboardWrite: Bool = false

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
        toolbarSize = try container.decodeIfPresent(ToolbarSize.self, forKey: .toolbarSize) ?? .regular
        enabledShortcutPacks = try container.decodeIfPresent([ShortcutPackID].self, forKey: .enabledShortcutPacks) ?? [.shell]
        favoriteShortcuts = try container.decodeIfPresent([Shortcut].self, forKey: .favoriteShortcuts) ?? []
        customizedPacks = try container.decodeIfPresent([ShortcutPackID: [Shortcut]].self, forKey: .customizedPacks) ?? [:]
        eventNotifications = try container.decodeIfPresent(EventNotificationSettings.self, forKey: .eventNotifications) ?? EventNotificationSettings()
        useMetalRenderer = try container.decodeIfPresent(Bool.self, forKey: .useMetalRenderer) ?? false
        metalBufferingMode = try container.decodeIfPresent(TerminalMetalBuffering.self, forKey: .metalBufferingMode) ?? .perRow
        preventDeviceSleepWhileConnected = try container.decodeIfPresent(Bool.self, forKey: .preventDeviceSleepWhileConnected) ?? false
        allowRemoteClipboardWrite = try container.decodeIfPresent(Bool.self, forKey: .allowRemoteClipboardWrite) ?? false
    }
}

enum ToolbarSize: String, Codable, Sendable, CaseIterable {
    case compact
    case regular
    case large

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }

    func rowHeight(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 54 : 44
        case .regular: return isPad ? 62 : 48
        case .large: return isPad ? 72 : 56
        }
    }

    func keyHeight(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 48 : 38
        case .regular: return isPad ? 56 : 42
        case .large: return isPad ? 66 : 50
        }
    }

    func keyFontSize(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 17 : 15
        case .regular: return isPad ? 19 : 17
        case .large: return isPad ? 22 : 19
        }
    }

    func keyCornerRadius(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 10 : 8
        case .regular: return isPad ? 12 : 9
        case .large: return isPad ? 14 : 11
        }
    }

    func glyphTarget(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 50 : 40
        case .regular: return isPad ? 58 : 44
        case .large: return isPad ? 68 : 48
        }
    }

    func glyphPointSize(isPad: Bool) -> CGFloat {
        switch self {
        case .compact: return isPad ? 19 : 15
        case .regular: return isPad ? 22 : 17
        case .large: return isPad ? 25 : 19
        }
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

enum TerminalMetalBuffering: String, Codable, Sendable, CaseIterable {
    case perRow
    case perFrame

    var displayName: String {
        switch self {
        case .perRow: return "Per Row"
        case .perFrame: return "Per Frame"
        }
    }

    var description: String {
        switch self {
        case .perRow: return "Caches rows, redraws only changes"
        case .perFrame: return "Redraws all rows each frame, better for full-screen TUIs"
        }
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
