import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    @ObservedObject var keyManagerViewModel: KeyManagerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            NavigationLink {
                KeyManagerView(viewModel: keyManagerViewModel)
            } label: {
                Label("SSH Keys", systemImage: "key")
            }

            NavigationLink {
                VisualSettingsView(viewModel: appearanceViewModel)
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }

            NavigationLink {
                KeyboardSettingsView(viewModel: appearanceViewModel)
            } label: {
                Label("Keyboard", systemImage: "keyboard")
            }

            NavigationLink {
                NotificationSettingsView(viewModel: appearanceViewModel)
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }

            NavigationLink {
                VoiceInputSettingsView()
            } label: {
                Label("Voice Input", systemImage: "mic")
            }

            Section("Behavior") {
                Toggle("Prevent device sleep while connected", isOn: binding(\.preventDeviceSleepWhileConnected))
            }

            Section {
                NavigationLink {
                    GettingStartedView()
                } label: {
                    Label("Getting Started", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TerminalAppearance, T>) -> Binding<T> {
        Binding(
            get: { appearanceViewModel.appearance[keyPath: keyPath] },
            set: { newValue in
                var updated = appearanceViewModel.appearance
                updated[keyPath: keyPath] = newValue
                Task { await appearanceViewModel.update(updated) }
            }
        )
    }
}
