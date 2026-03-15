import SwiftUI

struct VoiceInputSettingsView: View {
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = false
    @State private var modelStatus: ModelStatus = .unknown
    @State private var isDownloading = false
    @State private var downloadError: String?

    private enum ModelStatus {
        case unknown, notDownloaded, downloaded, downloading
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
                    switch modelStatus {
                    case .unknown:
                        HStack {
                            Text("Checking model...")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    case .notDownloaded:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model not downloaded")
                                .foregroundStyle(.secondary)
                            Text("The speech recognition model (~40 MB) will be downloaded on first use, or you can download it now.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            if let error = downloadError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button("Download Now") {
                                downloadModel()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isDownloading)
                        }
                        .padding(.vertical, 4)
                    case .downloading:
                        HStack {
                            Text("Downloading model...")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    case .downloaded:
                        HStack {
                            Text("Model ready")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Whisper Model")
                } footer: {
                    Text("Speech is processed entirely on-device using WhisperKit. No audio data leaves your device.")
                }
            }
        }
        .navigationTitle("Voice Input")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkModelStatus()
        }
    }

    private func checkModelStatus() async {
        let service = WhisperService()
        modelStatus = service.isModelCached() ? .downloaded : .notDownloaded
    }

    private func downloadModel() {
        isDownloading = true
        downloadError = nil
        modelStatus = .downloading

        Task {
            let service = WhisperService()
            do {
                try await service.ensureModelReady()
                modelStatus = .downloaded
            } catch {
                modelStatus = .notDownloaded
                downloadError = error.localizedDescription
            }
            isDownloading = false
        }
    }
}
