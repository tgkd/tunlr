import SwiftUI

struct ConnectionListView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    var onConnect: (SSHConnectionProfile) -> Void

    @State private var showingEditor = false
    @State private var editingProfile: SSHConnectionProfile?
    @State private var showingKeyManager = false

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
                    ConnectionRow(profile: profile)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onConnect(profile)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                onConnect(profile)
                            } label: {
                                Label("Connect", systemImage: "bolt.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    try? await viewModel.deleteProfile(id: profile.id)
                                }
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
                    showingKeyManager = true
                } label: {
                    Image(systemName: "key.fill")
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
        .task {
            await viewModel.loadProfiles()
        }
    }
}

struct ConnectionRow: View {
    let profile: SSHConnectionProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(profile.username)@\(profile.host)")
                    .font(.body.monospaced())
                if profile.port != 22 {
                    Text(":\(profile.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                authBadge
            }
            if let lastConnected = profile.lastConnected {
                Text(lastConnected, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var authBadge: some View {
        switch profile.authMethod {
        case .secureEnclaveKey:
            Label("SE", systemImage: "cpu")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .importedKey:
            Label("Key", systemImage: "key")
                .font(.caption2)
                .foregroundStyle(.green)
        case .password:
            Label("Pass", systemImage: "lock")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
