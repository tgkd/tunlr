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
                VoiceInputSettingsView()
            } label: {
                Label("Voice Input", systemImage: "mic")
            }

            Section {
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
}
