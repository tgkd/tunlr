import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ConnectionViewModel
    @ObservedObject var sessionManager: SSHSessionManager

    init(profileStore: ProfileStore, keyManager: KeyManager, sessionManager: SSHSessionManager) {
        _viewModel = StateObject(wrappedValue: ConnectionViewModel(
            profileStore: profileStore,
            keyManager: keyManager
        ))
        self.sessionManager = sessionManager
    }

    @State private var selectedProfile: SSHConnectionProfile?
    @State private var showTerminal = false

    var body: some View {
        NavigationStack {
            ConnectionListView(viewModel: viewModel) { profile in
                selectedProfile = profile
                showTerminal = true
            }
            .navigationDestination(isPresented: $showTerminal) {
                if let profile = selectedProfile, let session = sessionManager.activeSession {
                    TerminalScreen(
                        profile: profile,
                        sshSession: session,
                        onDisconnect: {
                            showTerminal = false
                            selectedProfile = nil
                        }
                    )
                    .navigationBarBackButtonHidden()
                }
            }
        }
        .onChange(of: showTerminal) { _, isShowing in
            if isShowing, let profile = selectedProfile {
                Task {
                    try? await sessionManager.startSession(for: profile)
                    try? await viewModel.markConnected(id: profile.id)
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
}
