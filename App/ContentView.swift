import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ConnectionViewModel
    @ObservedObject var sessionManager: SSHSessionManager
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(profileStore: ProfileStore, keyManager: KeyManager, sessionManager: SSHSessionManager, appearanceViewModel: AppearanceViewModel) {
        _viewModel = StateObject(wrappedValue: ConnectionViewModel(
            profileStore: profileStore,
            keyManager: keyManager
        ))
        self.sessionManager = sessionManager
        self.appearanceViewModel = appearanceViewModel
    }

    @State private var selectedProfile: SSHConnectionProfile?
    @State private var showTerminal = false
    @State private var connectionError: String?
    @State private var showingConnectionError = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var isSwitchingConnection = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    connectionList
                } detail: {
                    if showTerminal {
                        terminalOrConnecting
                    } else {
                        ContentUnavailableView(
                            "No Active Session",
                            systemImage: "network",
                            description: Text("Select a connection to start.")
                        )
                    }
                }
            } else {
                NavigationStack {
                    connectionList
                        .navigationDestination(isPresented: $showTerminal) {
                            terminalOrConnecting
                        }
                }
            }
        }
        .alert("Connection Failed", isPresented: $showingConnectionError) {
            Button("OK") {
                showTerminal = false
                selectedProfile = nil
            }
        } message: {
            Text("Could not connect to the server.")
        }
        .alert("Host Key Changed", isPresented: Binding(
            get: { sessionManager.pendingHostKeyMismatch != nil },
            set: { presented in if !presented { sessionManager.dismissPendingHostKey() } }
        ), presenting: sessionManager.pendingHostKeyMismatch) { pending in
            Button("Trust & Connect", role: .destructive) {
                guard let profile = selectedProfile else { return }
                Task {
                    do {
                        try await sessionManager.trust(pending)
                        try await sessionManager.startSession(for: profile)
                        try? await viewModel.markConnected(id: profile.id)
                    } catch SSHSessionManagerError.superseded {
                    } catch {
                        if sessionManager.pendingHostKeyMismatch == nil {
                            connectionError = error.localizedDescription
                            showingConnectionError = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                sessionManager.dismissPendingHostKey()
                showTerminal = false
                selectedProfile = nil
            }
        } message: { pending in
            Text("""
            The host key for \(pending.hostname):\(String(pending.port)) has changed. This could indicate a man-in-the-middle attack.

            Stored:   \(pending.existingFingerprint)
            Received: \(pending.newFingerprint)

            Only continue if you expected this change.
            """)
        }
        .onChange(of: showTerminal) { _, isShowing in
            if sizeClass == .regular {
                columnVisibility = isShowing ? .detailOnly : .doubleColumn
            }
            if isShowing, let profile = selectedProfile {
                Task {
                    do {
                        try await sessionManager.startSession(for: profile)
                        try? await viewModel.markConnected(id: profile.id)
                    } catch SSHSessionManagerError.superseded {
                    } catch {
                        if sessionManager.pendingHostKeyMismatch == nil {
                            connectionError = error.localizedDescription
                            showingConnectionError = true
                        }
                    }
                }
            } else if !isShowing {
                Task {
                    await sessionManager.disconnect()
                }
            }
        }
        .onChange(of: sessionManager.restoredProfileID) { _, profileID in
            guard let profileID else { return }
            Task {
                await viewModel.loadProfiles()
                if let profile = viewModel.profiles.first(where: { $0.id == profileID }),
                   profile.autoReconnect {
                    selectedProfile = profile
                    showTerminal = true
                }
                await sessionManager.clearRestoredSession()
            }
        }
        .onChange(of: sessionManager.state) { oldState, newState in
            guard showTerminal, newState == .idle else { return }
            switch oldState {
            case .backgrounded, .reconnecting:
                showTerminal = false
                selectedProfile = nil
            case .idle, .active:
                break
            }
        }
    }

    private var isManagerDrivenTeardown: Bool {
        switch sessionManager.state {
        case .backgrounded, .reconnecting: return true
        case .idle, .active: return false
        }
    }

    private var connectionList: some View {
        ConnectionListView(
            viewModel: viewModel,
            appearanceViewModel: appearanceViewModel,
            activeProfileID: showTerminal ? selectedProfile?.id : nil
        ) { profile in
            connectToProfile(profile)
        }
    }

    @ViewBuilder
    private var terminalOrConnecting: some View {
        if let profile = selectedProfile {
            if let session = sessionManager.activeSession {
                TerminalScreen(
                    profile: profile,
                    sshSession: session,
                    appearanceViewModel: appearanceViewModel,
                    onDisconnect: {
                        guard !isSwitchingConnection, !isManagerDrivenTeardown else { return }
                        showTerminal = false
                        selectedProfile = nil
                    }
                )
                .navigationBarBackButtonHidden()
                .id(ObjectIdentifier(session))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to \(profile.host)...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showTerminal = false
                            selectedProfile = nil
                        }
                    }
                }
            }
        }
    }

    private func connectToProfile(_ profile: SSHConnectionProfile) {
        let wasShowingTerminal = showTerminal
        selectedProfile = profile
        showTerminal = true

        if sizeClass == .regular {
            columnVisibility = .detailOnly
        }

        if wasShowingTerminal {
            isSwitchingConnection = true
            Task {
                await sessionManager.disconnect()
                do {
                    try await sessionManager.startSession(for: profile)
                    try? await viewModel.markConnected(id: profile.id)
                } catch SSHSessionManagerError.superseded {
                } catch {
                    if sessionManager.pendingHostKeyMismatch == nil {
                        connectionError = error.localizedDescription
                        showingConnectionError = true
                    }
                }
                isSwitchingConnection = false
            }
        }
    }
}
