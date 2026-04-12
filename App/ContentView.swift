import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ConnectionViewModel
    @ObservedObject var sessionManager: SSHSessionManager
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    @ObservedObject var approvalCoordinator: HostKeyApprovalCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(profileStore: ProfileStore, keyManager: KeyManager, sessionManager: SSHSessionManager, appearanceViewModel: AppearanceViewModel, approvalCoordinator: HostKeyApprovalCoordinator) {
        _viewModel = StateObject(wrappedValue: ConnectionViewModel(
            profileStore: profileStore,
            keyManager: keyManager
        ))
        self.sessionManager = sessionManager
        self.appearanceViewModel = appearanceViewModel
        self.approvalCoordinator = approvalCoordinator
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
        .sheet(item: $approvalCoordinator.pendingRequest) { request in
            HostVerificationSheet(
                request: request,
                onTrust: { approvalCoordinator.userTrusted() },
                onCancel: { approvalCoordinator.userRejected() }
            )
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
                    } catch {
                        connectionError = error.localizedDescription
                        showingConnectionError = true
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
                if let profile = viewModel.profiles.first(where: { $0.id == profileID }) {
                    selectedProfile = profile
                    showTerminal = true
                }
                await sessionManager.clearRestoredSession()
            }
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
                        if !isSwitchingConnection {
                            showTerminal = false
                            selectedProfile = nil
                        }
                    }
                )
                .navigationBarBackButtonHidden()
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
                } catch {
                    connectionError = error.localizedDescription
                    showingConnectionError = true
                }
                isSwitchingConnection = false
            }
        }
    }
}
