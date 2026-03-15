import Foundation

enum ShortcutPackCatalog {
    static func shortcuts(for packID: ShortcutPackID) -> [Shortcut] {
        switch packID {
        case .favorites: return []
        case .shell: return shell
        case .tmux: return tmux
        case .vim: return vim
        case .claudeCode: return claudeCode
        }
    }

    static let shell: [Shortcut] = [
        Shortcut(label: "Interrupt", shortcutDisplay: "Ctrl+C", icon: "xmark.octagon", bytes: [0x03]),
        Shortcut(label: "Suspend", shortcutDisplay: "Ctrl+Z", icon: "pause", bytes: [0x1A]),
        Shortcut(label: "End of Input", shortcutDisplay: "Ctrl+D", icon: "eject", bytes: [0x04]),
        Shortcut(label: "Clear Screen", shortcutDisplay: "Ctrl+L", icon: "sparkles.rectangle.stack", bytes: [0x0C]),
        Shortcut(label: "Line Start", shortcutDisplay: "Ctrl+A", icon: "arrow.left.to.line", bytes: [0x01]),
        Shortcut(label: "Line End", shortcutDisplay: "Ctrl+E", icon: "arrow.right.to.line", bytes: [0x05]),
        Shortcut(label: "Delete Word", shortcutDisplay: "Ctrl+W", icon: "delete.backward", bytes: [0x17]),
        Shortcut(label: "Kill Line", shortcutDisplay: "Ctrl+U", icon: "strikethrough", bytes: [0x15]),
        Shortcut(label: "Kill to End", shortcutDisplay: "Ctrl+K", icon: "text.line.last.and.arrowtriangle.forward", bytes: [0x0B]),
        Shortcut(label: "Search History", shortcutDisplay: "Ctrl+R", icon: "clock.arrow.circlepath", bytes: [0x12]),
        Shortcut(label: "Cancel Search", shortcutDisplay: "Ctrl+G", icon: "bell", bytes: [0x07]),
        Shortcut(label: "Swap Chars", shortcutDisplay: "Ctrl+T", icon: "arrow.left.arrow.right", bytes: [0x14]),
    ]

    static let tmux: [Shortcut] = [
        Shortcut(label: "New Window", shortcutDisplay: "Prefix c", icon: "plus.rectangle", bytes: [0x02, 0x63]),
        Shortcut(label: "Next Window", shortcutDisplay: "Prefix n", icon: "arrow.right", bytes: [0x02, 0x6E]),
        Shortcut(label: "Prev Window", shortcutDisplay: "Prefix p", icon: "arrow.left", bytes: [0x02, 0x70]),
        Shortcut(label: "Last Window", shortcutDisplay: "Prefix l", icon: "arrow.uturn.left", bytes: [0x02, 0x6C]),
        Shortcut(label: "Split Horiz", shortcutDisplay: "Prefix \"", icon: "rectangle.split.1x2", bytes: [0x02, 0x22]),
        Shortcut(label: "Split Vert", shortcutDisplay: "Prefix %", icon: "rectangle.split.2x1", bytes: [0x02, 0x25]),
        Shortcut(label: "Next Pane", shortcutDisplay: "Prefix o", icon: "arrow.right.square", bytes: [0x02, 0x6F]),
        Shortcut(label: "Zoom Pane", shortcutDisplay: "Prefix z", icon: "arrow.up.left.and.arrow.down.right", bytes: [0x02, 0x7A]),
        Shortcut(label: "Detach", shortcutDisplay: "Prefix d", icon: "arrow.uturn.backward", bytes: [0x02, 0x64]),
        Shortcut(label: "Rename Window", shortcutDisplay: "Prefix ,", icon: "pencil", bytes: [0x02, 0x2C]),
        Shortcut(label: "List Windows", shortcutDisplay: "Prefix w", icon: "list.bullet", bytes: [0x02, 0x77]),
        Shortcut(label: "Kill Pane", shortcutDisplay: "Prefix x", icon: "xmark.rectangle", bytes: [0x02, 0x78]),
    ]

    static let vim: [Shortcut] = [
        Shortcut(label: "Save", shortcutDisplay: ":w", icon: "square.and.arrow.down", bytes: [0x1B] + Array(":w\r".utf8)),
        Shortcut(label: "Quit", shortcutDisplay: ":q", icon: "xmark.square", bytes: [0x1B] + Array(":q\r".utf8)),
        Shortcut(label: "Save & Quit", shortcutDisplay: ":wq", icon: "checkmark.square", bytes: [0x1B] + Array(":wq\r".utf8)),
        Shortcut(label: "Force Quit", shortcutDisplay: ":q!", icon: "xmark.octagon", bytes: [0x1B] + Array(":q!\r".utf8)),
        Shortcut(label: "Undo", shortcutDisplay: "u", icon: "arrow.uturn.backward", bytes: [0x1B, 0x75]),
        Shortcut(label: "Redo", shortcutDisplay: "Ctrl+R", icon: "arrow.uturn.forward", bytes: [0x12]),
        Shortcut(label: "Search", shortcutDisplay: "/", icon: "magnifyingglass", bytes: [0x1B, 0x2F]),
        Shortcut(label: "Next Match", shortcutDisplay: "n", icon: "arrow.down", bytes: [0x1B, 0x6E]),
        Shortcut(label: "Insert Mode", shortcutDisplay: "i", icon: "character.cursor.ibeam", bytes: [0x1B, 0x69]),
        Shortcut(label: "Normal Mode", shortcutDisplay: "Esc", icon: "escape", bytes: [0x1B]),
        Shortcut(label: "Visual Mode", shortcutDisplay: "v", icon: "selection.pin.in.out", bytes: [0x1B, 0x76]),
        Shortcut(label: "Delete Line", shortcutDisplay: "dd", icon: "trash", bytes: [0x1B, 0x64, 0x64]),
    ]

    static let claudeCode: [Shortcut] = [
        Shortcut(label: "Submit", shortcutDisplay: "Enter", icon: "return", bytes: [0x0D]),
        Shortcut(label: "New Line", shortcutDisplay: "Opt+Enter", icon: "text.append", bytes: [0x1B, 0x0D]),
        Shortcut(label: "Accept", shortcutDisplay: "y", icon: "checkmark.circle", bytes: [0x79]),
        Shortcut(label: "Reject", shortcutDisplay: "n", icon: "xmark.circle", bytes: [0x6E]),
        Shortcut(label: "Yes to All", shortcutDisplay: "!", icon: "checkmark.circle.fill", bytes: [0x21]),
        Shortcut(label: "Cancel", shortcutDisplay: "Esc", icon: "escape", bytes: [0x1B]),
        Shortcut(label: "Interrupt", shortcutDisplay: "Ctrl+C", icon: "xmark.octagon", bytes: [0x03]),
        Shortcut(label: "Undo", shortcutDisplay: "Ctrl+_", icon: "arrow.uturn.backward", bytes: [0x1F]),
        Shortcut(label: "Cycle Mode", shortcutDisplay: "Shift+Tab", icon: "arrow.triangle.2.circlepath", bytes: [0x1B, 0x5B, 0x5A]),
        Shortcut(label: "History", shortcutDisplay: "Ctrl+R", icon: "clock.arrow.circlepath", bytes: [0x12]),
    ]
}
