import UIKit
import SwiftUI
import SwiftTerm

struct ColorValue: Sendable, Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: 1.0
        )
    }

    var swiftUIColor: SwiftUI.Color {
        SwiftUI.Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }

    var swiftTermColor: SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(red) * 257, green: UInt16(green) * 257, blue: UInt16(blue) * 257)
    }
}

struct TerminalTheme: Sendable {
    let name: TerminalThemeName
    let displayName: String
    let backgroundColor: ColorValue
    let foregroundColor: ColorValue
    let cursorColor: ColorValue
    let ansiColors: [ColorValue]
    let isDark: Bool
}

enum TerminalThemeCatalog {
    static func theme(for name: TerminalThemeName) -> TerminalTheme {
        switch name {
        case .defaultDark: return defaultDark
        case .solarizedDark: return solarizedDark
        case .solarizedLight: return solarizedLight
        case .dracula: return dracula
        case .nord: return nord
        case .monokai: return monokai
        case .oneDark: return oneDark
        case .githubDark: return githubDark
        case .gruvboxDark: return gruvboxDark
        }
    }

    static var allThemes: [TerminalTheme] {
        TerminalThemeName.allCases.map { theme(for: $0) }
    }

    // MARK: - Theme Definitions

    private static let defaultDark = TerminalTheme(
        name: .defaultDark,
        displayName: "Default Dark",
        backgroundColor: ColorValue(red: 0, green: 0, blue: 0),
        foregroundColor: ColorValue(red: 229, green: 229, blue: 229),
        cursorColor: ColorValue(red: 229, green: 229, blue: 229),
        ansiColors: [
            ColorValue(red: 0, green: 0, blue: 0),         // black
            ColorValue(red: 204, green: 0, blue: 0),       // red
            ColorValue(red: 0, green: 204, blue: 0),       // green
            ColorValue(red: 204, green: 204, blue: 0),     // yellow
            ColorValue(red: 0, green: 0, blue: 204),       // blue
            ColorValue(red: 204, green: 0, blue: 204),     // magenta
            ColorValue(red: 0, green: 204, blue: 204),     // cyan
            ColorValue(red: 204, green: 204, blue: 204),   // white
            ColorValue(red: 85, green: 85, blue: 85),      // bright black
            ColorValue(red: 255, green: 85, blue: 85),     // bright red
            ColorValue(red: 85, green: 255, blue: 85),     // bright green
            ColorValue(red: 255, green: 255, blue: 85),    // bright yellow
            ColorValue(red: 85, green: 85, blue: 255),     // bright blue
            ColorValue(red: 255, green: 85, blue: 255),    // bright magenta
            ColorValue(red: 85, green: 255, blue: 255),    // bright cyan
            ColorValue(red: 255, green: 255, blue: 255),   // bright white
        ],
        isDark: true
    )

    private static let solarizedDark = TerminalTheme(
        name: .solarizedDark,
        displayName: "Solarized Dark",
        backgroundColor: ColorValue(red: 0, green: 43, blue: 54),
        foregroundColor: ColorValue(red: 131, green: 148, blue: 150),
        cursorColor: ColorValue(red: 131, green: 148, blue: 150),
        ansiColors: [
            ColorValue(red: 7, green: 54, blue: 66),       // black
            ColorValue(red: 220, green: 50, blue: 47),     // red
            ColorValue(red: 133, green: 153, blue: 0),     // green
            ColorValue(red: 181, green: 137, blue: 0),     // yellow
            ColorValue(red: 38, green: 139, blue: 210),    // blue
            ColorValue(red: 211, green: 54, blue: 130),    // magenta
            ColorValue(red: 42, green: 161, blue: 152),    // cyan
            ColorValue(red: 238, green: 232, blue: 213),   // white
            ColorValue(red: 0, green: 43, blue: 54),       // bright black
            ColorValue(red: 203, green: 75, blue: 22),     // bright red
            ColorValue(red: 88, green: 110, blue: 117),    // bright green
            ColorValue(red: 101, green: 123, blue: 131),   // bright yellow
            ColorValue(red: 131, green: 148, blue: 150),   // bright blue
            ColorValue(red: 108, green: 113, blue: 196),   // bright magenta
            ColorValue(red: 147, green: 161, blue: 161),   // bright cyan
            ColorValue(red: 253, green: 246, blue: 227),   // bright white
        ],
        isDark: true
    )

    private static let solarizedLight = TerminalTheme(
        name: .solarizedLight,
        displayName: "Solarized Light",
        backgroundColor: ColorValue(red: 253, green: 246, blue: 227),
        foregroundColor: ColorValue(red: 101, green: 123, blue: 131),
        cursorColor: ColorValue(red: 101, green: 123, blue: 131),
        ansiColors: [
            ColorValue(red: 7, green: 54, blue: 66),
            ColorValue(red: 220, green: 50, blue: 47),
            ColorValue(red: 133, green: 153, blue: 0),
            ColorValue(red: 181, green: 137, blue: 0),
            ColorValue(red: 38, green: 139, blue: 210),
            ColorValue(red: 211, green: 54, blue: 130),
            ColorValue(red: 42, green: 161, blue: 152),
            ColorValue(red: 238, green: 232, blue: 213),
            ColorValue(red: 0, green: 43, blue: 54),
            ColorValue(red: 203, green: 75, blue: 22),
            ColorValue(red: 88, green: 110, blue: 117),
            ColorValue(red: 101, green: 123, blue: 131),
            ColorValue(red: 131, green: 148, blue: 150),
            ColorValue(red: 108, green: 113, blue: 196),
            ColorValue(red: 147, green: 161, blue: 161),
            ColorValue(red: 253, green: 246, blue: 227),
        ],
        isDark: false
    )

    private static let dracula = TerminalTheme(
        name: .dracula,
        displayName: "Dracula",
        backgroundColor: ColorValue(red: 40, green: 42, blue: 54),
        foregroundColor: ColorValue(red: 248, green: 248, blue: 242),
        cursorColor: ColorValue(red: 248, green: 248, blue: 242),
        ansiColors: [
            ColorValue(red: 33, green: 34, blue: 44),
            ColorValue(red: 255, green: 85, blue: 85),
            ColorValue(red: 80, green: 250, blue: 123),
            ColorValue(red: 241, green: 250, blue: 140),
            ColorValue(red: 189, green: 147, blue: 249),
            ColorValue(red: 255, green: 121, blue: 198),
            ColorValue(red: 139, green: 233, blue: 253),
            ColorValue(red: 248, green: 248, blue: 242),
            ColorValue(red: 98, green: 114, blue: 164),
            ColorValue(red: 255, green: 110, blue: 110),
            ColorValue(red: 105, green: 255, blue: 148),
            ColorValue(red: 255, green: 255, blue: 165),
            ColorValue(red: 214, green: 172, blue: 255),
            ColorValue(red: 255, green: 146, blue: 223),
            ColorValue(red: 164, green: 255, blue: 255),
            ColorValue(red: 255, green: 255, blue: 255),
        ],
        isDark: true
    )

    private static let nord = TerminalTheme(
        name: .nord,
        displayName: "Nord",
        backgroundColor: ColorValue(red: 46, green: 52, blue: 64),
        foregroundColor: ColorValue(red: 216, green: 222, blue: 233),
        cursorColor: ColorValue(red: 216, green: 222, blue: 233),
        ansiColors: [
            ColorValue(red: 59, green: 66, blue: 82),
            ColorValue(red: 191, green: 97, blue: 106),
            ColorValue(red: 163, green: 190, blue: 140),
            ColorValue(red: 235, green: 203, blue: 139),
            ColorValue(red: 129, green: 161, blue: 193),
            ColorValue(red: 180, green: 142, blue: 173),
            ColorValue(red: 136, green: 192, blue: 208),
            ColorValue(red: 229, green: 233, blue: 240),
            ColorValue(red: 76, green: 86, blue: 106),
            ColorValue(red: 191, green: 97, blue: 106),
            ColorValue(red: 163, green: 190, blue: 140),
            ColorValue(red: 235, green: 203, blue: 139),
            ColorValue(red: 129, green: 161, blue: 193),
            ColorValue(red: 180, green: 142, blue: 173),
            ColorValue(red: 143, green: 188, blue: 187),
            ColorValue(red: 236, green: 239, blue: 244),
        ],
        isDark: true
    )

    private static let monokai = TerminalTheme(
        name: .monokai,
        displayName: "Monokai",
        backgroundColor: ColorValue(red: 39, green: 40, blue: 34),
        foregroundColor: ColorValue(red: 248, green: 248, blue: 242),
        cursorColor: ColorValue(red: 248, green: 248, blue: 242),
        ansiColors: [
            ColorValue(red: 39, green: 40, blue: 34),
            ColorValue(red: 249, green: 38, blue: 114),
            ColorValue(red: 166, green: 226, blue: 46),
            ColorValue(red: 244, green: 191, blue: 117),
            ColorValue(red: 102, green: 217, blue: 239),
            ColorValue(red: 174, green: 129, blue: 255),
            ColorValue(red: 161, green: 239, blue: 228),
            ColorValue(red: 248, green: 248, blue: 242),
            ColorValue(red: 117, green: 113, blue: 94),
            ColorValue(red: 249, green: 38, blue: 114),
            ColorValue(red: 166, green: 226, blue: 46),
            ColorValue(red: 244, green: 191, blue: 117),
            ColorValue(red: 102, green: 217, blue: 239),
            ColorValue(red: 174, green: 129, blue: 255),
            ColorValue(red: 161, green: 239, blue: 228),
            ColorValue(red: 249, green: 248, blue: 245),
        ],
        isDark: true
    )

    private static let oneDark = TerminalTheme(
        name: .oneDark,
        displayName: "One Dark",
        backgroundColor: ColorValue(red: 40, green: 44, blue: 52),
        foregroundColor: ColorValue(red: 171, green: 178, blue: 191),
        cursorColor: ColorValue(red: 171, green: 178, blue: 191),
        ansiColors: [
            ColorValue(red: 40, green: 44, blue: 52),
            ColorValue(red: 224, green: 108, blue: 117),
            ColorValue(red: 152, green: 195, blue: 121),
            ColorValue(red: 229, green: 192, blue: 123),
            ColorValue(red: 97, green: 175, blue: 239),
            ColorValue(red: 198, green: 120, blue: 221),
            ColorValue(red: 86, green: 182, blue: 194),
            ColorValue(red: 171, green: 178, blue: 191),
            ColorValue(red: 92, green: 99, blue: 112),
            ColorValue(red: 224, green: 108, blue: 117),
            ColorValue(red: 152, green: 195, blue: 121),
            ColorValue(red: 229, green: 192, blue: 123),
            ColorValue(red: 97, green: 175, blue: 239),
            ColorValue(red: 198, green: 120, blue: 221),
            ColorValue(red: 86, green: 182, blue: 194),
            ColorValue(red: 255, green: 255, blue: 255),
        ],
        isDark: true
    )

    private static let githubDark = TerminalTheme(
        name: .githubDark,
        displayName: "GitHub Dark",
        backgroundColor: ColorValue(red: 13, green: 17, blue: 23),
        foregroundColor: ColorValue(red: 230, green: 237, blue: 243),
        cursorColor: ColorValue(red: 230, green: 237, blue: 243),
        ansiColors: [
            ColorValue(red: 72, green: 81, blue: 94),
            ColorValue(red: 255, green: 123, blue: 114),
            ColorValue(red: 63, green: 185, blue: 80),
            ColorValue(red: 210, green: 153, blue: 34),
            ColorValue(red: 88, green: 166, blue: 255),
            ColorValue(red: 188, green: 140, blue: 255),
            ColorValue(red: 57, green: 216, blue: 207),
            ColorValue(red: 230, green: 237, blue: 243),
            ColorValue(red: 110, green: 118, blue: 129),
            ColorValue(red: 255, green: 123, blue: 114),
            ColorValue(red: 63, green: 185, blue: 80),
            ColorValue(red: 210, green: 153, blue: 34),
            ColorValue(red: 88, green: 166, blue: 255),
            ColorValue(red: 188, green: 140, blue: 255),
            ColorValue(red: 57, green: 216, blue: 207),
            ColorValue(red: 255, green: 255, blue: 255),
        ],
        isDark: true
    )

    private static let gruvboxDark = TerminalTheme(
        name: .gruvboxDark,
        displayName: "Gruvbox Dark",
        backgroundColor: ColorValue(red: 40, green: 40, blue: 40),
        foregroundColor: ColorValue(red: 235, green: 219, blue: 178),
        cursorColor: ColorValue(red: 235, green: 219, blue: 178),
        ansiColors: [
            ColorValue(red: 40, green: 40, blue: 40),
            ColorValue(red: 204, green: 36, blue: 29),
            ColorValue(red: 152, green: 151, blue: 26),
            ColorValue(red: 215, green: 153, blue: 33),
            ColorValue(red: 69, green: 133, blue: 136),
            ColorValue(red: 177, green: 98, blue: 134),
            ColorValue(red: 104, green: 157, blue: 106),
            ColorValue(red: 168, green: 153, blue: 132),
            ColorValue(red: 146, green: 131, blue: 116),
            ColorValue(red: 251, green: 73, blue: 52),
            ColorValue(red: 184, green: 187, blue: 38),
            ColorValue(red: 250, green: 189, blue: 47),
            ColorValue(red: 131, green: 165, blue: 152),
            ColorValue(red: 211, green: 134, blue: 155),
            ColorValue(red: 142, green: 192, blue: 124),
            ColorValue(red: 235, green: 219, blue: 178),
        ],
        isDark: true
    )
}
