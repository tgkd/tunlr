import SwiftUI

struct ConnectionListView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    var activeProfileID: UUID?
    var onConnect: (SSHConnectionProfile) -> Void

    @State private var showingEditor = false
    @State private var editingProfile: SSHConnectionProfile?
    @State private var showingSettings = false
    @State private var profileToDelete: SSHConnectionProfile?

    var body: some View {
        List {
            if viewModel.profiles.isEmpty {
                ContentUnavailableView(
                    "No Connections",
                    systemImage: "network",
                    description: Text("Tap + to add an SSH connection.")
                )
            } else {
                ForEach(viewModel.profiles) { profile in
                    let isActive = profile.id == activeProfileID
                    ConnectionRow(profile: profile, isActive: isActive)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isActive {
                                onConnect(profile)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !isActive {
                                Button {
                                    onConnect(profile)
                                } label: {
                                    Label("Connect", systemImage: "bolt.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                profileToDelete = profile
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingProfile = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                ConnectionEditorView(
                    viewModel: viewModel,
                    existingProfile: nil,
                    onSave: {
                        showingEditor = false
                    }
                )
            }
        }
        .sheet(item: $editingProfile) { profile in
            NavigationStack {
                ConnectionEditorView(
                    viewModel: viewModel,
                    existingProfile: profile,
                    onSave: {
                        editingProfile = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(
                    appearanceViewModel: appearanceViewModel,
                    keyManagerViewModel: KeyManagerViewModel(keyManager: viewModel.keyManager)
                )
            }
        }
        .alert("Delete Connection?", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    Task { try? await viewModel.deleteProfile(id: profile.id) }
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text("Delete \(profile.username)@\(profile.host)? This cannot be undone.")
            }
        }
        .task {
            await viewModel.loadProfiles()
        }
    }
}

struct ConnectionRow: View {
    let profile: SSHConnectionProfile
    var isActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
                Text("\(profile.username)@\(profile.host)")
                    .font(.body.monospaced())
                if profile.port != 22 {
                    Text(":\(profile.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                authIcon
            }
            if let lastConnected = profile.lastConnected {
                Text("Last connected: \(lastConnected.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var authIcon: some View {
        switch profile.authMethod {
        case .secureEnclaveKey:
            Image(systemName: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .importedKey:
            Image(systemName: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .password:
            Image(systemName: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
