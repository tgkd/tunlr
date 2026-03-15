import Foundation

@MainActor
final class AppearanceViewModel: ObservableObject {
    @Published var appearance: TerminalAppearance = .init()
    private let store: AppearanceStore

    init(store: AppearanceStore) {
        self.store = store
    }

    func load() async {
        appearance = await store.currentAppearance()
    }

    func update(_ newAppearance: TerminalAppearance) async {
        appearance = newAppearance
        try? await store.update(newAppearance)
    }

    var currentTheme: TerminalTheme {
        TerminalThemeCatalog.theme(for: appearance.themeName)
    }
}
