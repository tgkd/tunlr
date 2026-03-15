import SwiftUI

struct KeyboardSettingsView: View {
    @ObservedObject var viewModel: AppearanceViewModel

    private var disabledPacks: [ShortcutPackID] {
        ShortcutPackID.allCases.filter {
            $0 != .favorites && !viewModel.appearance.enabledShortcutPacks.contains($0)
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    KeysPanelEditView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label("Keys", systemImage: "keyboard")
                        Spacer()
                        Text("\(viewModel.appearance.toolbarButtons.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Toolbar")
            } footer: {
                Text("Custom keys always appear as the first panel.")
            }

            Section("Shortcut Packs") {
                ForEach(viewModel.appearance.enabledShortcutPacks) { packID in
                    NavigationLink {
                        ShortcutPackEditView(viewModel: viewModel, packID: packID)
                    } label: {
                        HStack {
                            Label(packID.displayName, systemImage: packID.icon)
                            Spacer()
                            Text("\(viewModel.appearance.shortcuts(for: packID).count)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    var updated = viewModel.appearance
                    updated.enabledShortcutPacks.remove(atOffsets: offsets)
                    Task { await viewModel.update(updated) }
                }
            }

            if !disabledPacks.isEmpty {
                Section("Available Packs") {
                    ForEach(disabledPacks) { packID in
                        Button {
                            var updated = viewModel.appearance
                            updated.enabledShortcutPacks.append(packID)
                            Task { await viewModel.update(updated) }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                Label(packID.displayName, systemImage: packID.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(ShortcutPackCatalog.shortcuts(for: packID).count)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !viewModel.appearance.favoriteShortcuts.isEmpty {
                Section("Favorites (\(viewModel.appearance.favoriteShortcuts.count))") {
                    NavigationLink {
                        FavoritesEditView(viewModel: viewModel)
                    } label: {
                        Label("Edit Favorites", systemImage: "star")
                    }
                }
            }
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Keys Panel Edit

struct KeysPanelEditView: View {
    @ObservedObject var viewModel: AppearanceViewModel
    @State private var editMode: EditMode = .inactive

    private var available: [ToolbarButtonKind] {
        ToolbarButtonKind.allCases.filter { !viewModel.appearance.toolbarButtons.contains($0) }
    }

    var body: some View {
        List {
            Section("Active") {
                ForEach(viewModel.appearance.toolbarButtons) { kind in
                    HStack {
                        Text(kind.settingsLabel)
                        Spacer()
                        Text(kind.displayTitle)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .onMove { from, to in
                    var updated = viewModel.appearance
                    updated.toolbarButtons.move(fromOffsets: from, toOffset: to)
                    Task { await viewModel.update(updated) }
                }
                .onDelete { offsets in
                    var updated = viewModel.appearance
                    updated.toolbarButtons.remove(atOffsets: offsets)
                    Task { await viewModel.update(updated) }
                }
            }

            if !available.isEmpty {
                Section("Available") {
                    ForEach(available) { kind in
                        Button {
                            var updated = viewModel.appearance
                            updated.toolbarButtons.append(kind)
                            Task { await viewModel.update(updated) }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                Text(kind.settingsLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(kind.displayTitle)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
    }
}

// MARK: - Shortcut Pack Edit

struct ShortcutPackEditView: View {
    @ObservedObject var viewModel: AppearanceViewModel
    let packID: ShortcutPackID
    @State private var editMode: EditMode = .inactive

    private var activeShortcuts: [Shortcut] {
        viewModel.appearance.shortcuts(for: packID)
    }

    private var removedShortcuts: [Shortcut] {
        let defaults = ShortcutPackCatalog.shortcuts(for: packID)
        let active = activeShortcuts
        return defaults.filter { def in !active.contains(def) }
    }

    var body: some View {
        List {
            Section {
                ForEach(activeShortcuts) { shortcut in
                    HStack(spacing: 12) {
                        Image(systemName: shortcut.icon)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.label)
                            Text(shortcut.shortcutDisplay)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { from, to in
                    var shortcuts = activeShortcuts
                    shortcuts.move(fromOffsets: from, toOffset: to)
                    var updated = viewModel.appearance
                    updated.customizedPacks[packID] = shortcuts
                    Task { await viewModel.update(updated) }
                }
                .onDelete { offsets in
                    var shortcuts = activeShortcuts
                    shortcuts.remove(atOffsets: offsets)
                    var updated = viewModel.appearance
                    updated.customizedPacks[packID] = shortcuts
                    Task { await viewModel.update(updated) }
                }
            }

            if !removedShortcuts.isEmpty {
                Section("Removed") {
                    ForEach(removedShortcuts) { shortcut in
                        Button {
                            var shortcuts = activeShortcuts
                            shortcuts.append(shortcut)
                            var updated = viewModel.appearance
                            updated.customizedPacks[packID] = shortcuts
                            Task { await viewModel.update(updated) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                Image(systemName: shortcut.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shortcut.label)
                                        .foregroundStyle(.primary)
                                    Text(shortcut.shortcutDisplay)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if viewModel.appearance.customizedPacks[packID] != nil {
                Section {
                    Button("Reset to Defaults") {
                        var updated = viewModel.appearance
                        updated.customizedPacks.removeValue(forKey: packID)
                        Task { await viewModel.update(updated) }
                    }
                }
            }
        }
        .navigationTitle(packID.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
    }
}

// MARK: - Favorites Edit

struct FavoritesEditView: View {
    @ObservedObject var viewModel: AppearanceViewModel

    var body: some View {
        List {
            ForEach(viewModel.appearance.favoriteShortcuts) { shortcut in
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                    Image(systemName: shortcut.icon)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortcut.label)
                        Text(shortcut.shortcutDisplay)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { from, to in
                var updated = viewModel.appearance
                updated.favoriteShortcuts.move(fromOffsets: from, toOffset: to)
                Task { await viewModel.update(updated) }
            }
            .onDelete { offsets in
                var updated = viewModel.appearance
                updated.favoriteShortcuts.remove(atOffsets: offsets)
                Task { await viewModel.update(updated) }
            }

            Section {
                Button(role: .destructive) {
                    var updated = viewModel.appearance
                    updated.favoriteShortcuts.removeAll()
                    Task { await viewModel.update(updated) }
                } label: {
                    Label("Clear All Favorites", systemImage: "star.slash")
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
}
