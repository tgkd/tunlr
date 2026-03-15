import SwiftUI

struct VoiceInputSettingsView: View {
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = false
    @AppStorage("whisperModelSize") private var modelSizeRaw = WhisperModelSize.tiny.rawValue
    @State private var cachedModels: Set<WhisperModelSize> = []
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var modelToDelete: WhisperModelSize?

    private var selectedModel: WhisperModelSize {
        WhisperModelSize(rawValue: modelSizeRaw) ?? .tiny
    }

    var body: some View {
        List {
            Section {
                Toggle("Enable Voice Input", isOn: $voiceInputEnabled)
            } footer: {
                Text("Adds a microphone button to the terminal keyboard. Speak commands and review them before sending.")
            }

            if voiceInputEnabled {
                Section {
                    ForEach(WhisperModelSize.allCases, id: \.self) { size in
                        HStack {
                            Button {
                                modelSizeRaw = size.rawValue
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(size.displayName)
                                            .foregroundStyle(.primary)
                                        Text(size.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }

                            if cachedModels.contains(size) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }

                            if size.rawValue == modelSizeRaw {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if cachedModels.contains(size), size.rawValue != modelSizeRaw {
                                Button(role: .destructive) {
                                    modelToDelete = size
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Larger models are more accurate for technical commands but slower to transcribe. Swipe to delete unused models.")
                }

                if !cachedModels.contains(selectedModel) {
                    Section {
                        if isDownloading {
                            HStack {
                                Text("Downloading \(selectedModel.displayName)...")
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(selectedModel.displayName) model not downloaded")
                                    .foregroundStyle(.secondary)

                                if let error = downloadError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                Button("Download Now") {
                                    downloadModel()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 4)
                        }
                    } footer: {
                        Text("The model will be downloaded automatically on first use if not pre-downloaded.")
                    }
                }

                Section {
                } footer: {
                    Text("Speech is processed entirely on-device. No audio data leaves your device.")
                }
            }
        }
        .navigationTitle("Voice Input")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshCachedModels()
        }
        .onChange(of: modelSizeRaw) { _, _ in
            refreshCachedModels()
        }
        .alert("Delete Model", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    let service = WhisperService()
                    _ = service.deleteModel(for: model)
                    refreshCachedModels()
                }
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Delete the \(model.displayName) model? It can be re-downloaded later.")
            }
        }
    }

    private func refreshCachedModels() {
        let service = WhisperService()
        var cached = Set<WhisperModelSize>()
        for size in WhisperModelSize.allCases {
            if service.isModelCached(for: size) {
                cached.insert(size)
            }
        }
        cachedModels = cached
    }

    private func downloadModel() {
        isDownloading = true
        downloadError = nil

        Task {
            let service = WhisperService()
            do {
                try await service.ensureModelReady()
                refreshCachedModels()
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
        }
    }
}
