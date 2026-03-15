import UIKit

struct TerminalAppearance: Codable, Sendable, Equatable {
    var fontName: TerminalFontName = .sfMono
    var fontSize: CGFloat = 14
    var themeName: TerminalThemeName = .defaultDark
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
    case githubDark
    case gruvboxDark
}
