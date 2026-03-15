import SwiftUI
import UIKit

struct TerminalScreen: View {
    let profile: SSHConnectionProfile
    let sshSession: SSHSession
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    let onDisconnect: () -> Void

    @State private var terminalTitle: String = ""
    @State private var connectionState: ConnectionState = .disconnected
    @State private var showDisconnectAlert = false
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = false
    @State private var whisperService = WhisperService()
    @State private var whisperState: WhisperServiceState = .idle
    @State private var showComposeBar = false
    @State private var transcribedText = ""
    @State private var showMicPermissionAlert = false
    @Environment(\.dismiss) private var dismiss

    private var themeBackgroundColor: Color {
        appearanceViewModel.currentTheme.backgroundColor.swiftUIColor
    }

    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            themeBackgroundColor
                .ignoresSafeArea()

            TerminalViewRepresentable(
                sshSession: sshSession,
                terminalTitle: $terminalTitle,
                appearanceViewModel: appearanceViewModel,
                voiceInputEnabled: voiceInputEnabled,
                onMicrophoneTapped: { handleMicTap() }
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if showComposeBar {
                SpeechComposeBar(
                    state: whisperState,
                    transcribedText: $transcribedText,
                    onSend: { sendTranscription(withEnter: false) },
                    onRun: { sendTranscription(withEnter: true) },
                    onCancel: { cancelSpeech() },
                    onStopRecording: { stopRecording() }
                )
                .padding(.bottom, keyboardHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let bottomInset = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.keyWindow?.safeAreaInsets.bottom ?? 0
            let newHeight = max(0, screenHeight - frame.origin.y - bottomInset)
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = newHeight
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDisconnectAlert = true
                } label: {
                    connectionIndicator
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .principal) {
                Text(terminalTitle.isEmpty ? "\(profile.username)@\(profile.host)" : terminalTitle)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(appearanceViewModel.currentTheme.isDark ? .white : .primary)
                    .lineLimit(1)
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(appearanceViewModel.currentTheme.backgroundColor.swiftUIColor, for: .navigationBar)
        .toolbarColorScheme(appearanceViewModel.currentTheme.isDark ? .dark : .light, for: .navigationBar)
        .preferredColorScheme(appearanceViewModel.currentTheme.isDark ? .dark : .light)
        .alert("Disconnect", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await sshSession.disconnect()
                    onDisconnect()
                }
            }
        } message: {
            Text("Are you sure you want to disconnect from \(profile.host)?")
        }
        .alert("Microphone Access", isPresented: $showMicPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("tunlr needs microphone access for voice input. Enable it in Settings.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if showComposeBar {
                cancelSpeech()
            }
        }
        .task {
            await observeConnectionState()
        }
        .task {
            if voiceInputEnabled {
                try? await whisperService.ensureModelReady()
            }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch connectionState {
        case .connected:
            Circle()
                .fill(Color(red: 0.3, green: 0.85, blue: 0.4))
                .frame(width: 8, height: 8)
        case .connecting, .reconnecting:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.6)
        case .disconnected:
            Circle()
                .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                .frame(width: 8, height: 8)
        }
    }

    private func observeConnectionState() async {
        for await state in await sshSession.connectionStateStream() {
            connectionState = state
            if state == .disconnected {
                onDisconnect()
                return
            }
        }
    }

    private func handleMicTap() {
        Task {
            let permission = whisperService.checkMicrophonePermission()
            switch permission {
            case .undetermined:
                let granted = await whisperService.requestMicrophonePermission()
                if granted {
                    await startRecording()
                }
            case .granted:
                if whisperState == .recording {
                    stopRecording()
                } else {
                    await startRecording()
                }
            case .denied:
                showMicPermissionAlert = true
            }
        }
    }

    private func startRecording() async {
        transcribedText = ""
        whisperState = whisperService.isModelCached() ? .recording : .downloading
        withAnimation { showComposeBar = true }
        do {
            try await whisperService.startRecording()
            whisperState = .recording
        } catch {
            whisperState = .error(error.localizedDescription)
        }
    }

    private func stopRecording() {
        Task {
            whisperState = .transcribing
            let result = await whisperService.stopAndTranscribe()
            switch result {
            case .transcription(let text):
                transcribedText = text
                whisperState = .idle
            case .error(let message):
                whisperState = .error(message)
            }
        }
    }

    private func sendTranscription(withEnter: Bool) {
        let text = transcribedText
        guard !text.isEmpty else { return }
        withAnimation { showComposeBar = false }
        whisperState = .idle
        transcribedText = ""
        Task {
            try? await sshSession.write(Data(text.utf8))
            if withEnter {
                try? await sshSession.write(Data([0x0d]))
            }
        }
    }

    private func cancelSpeech() {
        Task {
            await whisperService.cancel()
        }
        withAnimation { showComposeBar = false }
        whisperState = .idle
        transcribedText = ""
    }
}

