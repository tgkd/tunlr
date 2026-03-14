import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ConnectionViewModel

    init(profileStore: ProfileStore, keyManager: KeyManager) {
        _viewModel = StateObject(wrappedValue: ConnectionViewModel(
            profileStore: profileStore,
            keyManager: keyManager
        ))
    }

    var body: some View {
        NavigationStack {
            ConnectionListView(viewModel: viewModel) { profile in
                // Connection handling will be wired in Task 12
            }
        }
    }
}
