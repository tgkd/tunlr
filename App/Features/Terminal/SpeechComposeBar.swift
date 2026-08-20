import SwiftUI

struct SpeechComposeBar: View {
    let state: WhisperServiceState
    let level: Float
    @Binding var transcribedText: String
    let onInsert: () -> Void
    let onRun: () -> Void
    let onCancel: () -> Void
    let onStopRecording: () -> Void
    let onRestart: () -> Void
    let onOpenSettings: () -> Void

    @State private var elapsed: Int = 0

    private static let glyphBox: CGFloat = 22

    private var isRecording: Bool { state == .recording }
    private var isTranscribing: Bool { state == .transcribing }

    var body: some View {
        Group {
            switch state {
            case .recording, .transcribing:
                dictationBar
            case .preparing:
                statusBar(title: "Preparing...")
            case .downloading:
                statusBar(title: "Downloading model...")
            case .noSpeech:
                noSpeechBar
            case .permissionDenied:
                permissionBar
            case .error(let message):
                errorBar(message: message)
            case .idle:
                transcriptCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .task(id: isRecording) {
            guard isRecording else { return }
            elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsed += 1
            }
        }
    }

    // MARK: - Dictating

    private var dictationBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(isTranscribing ? "Transcribing..." : "Dictating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeString)
                    .font(.system(size: 17, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if isTranscribing {
                Spacer(minLength: 0)
            } else {
                LevelMeter(level: level)
            }

            circularButton(systemImage: "xmark", accessibility: "Cancel dictation", action: onCancel)

            Button(action: onStopRecording) {
                Group {
                    if isTranscribing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(width: Self.glyphBox, height: Self.glyphBox)
            }
            .accessibilityLabel(isTranscribing ? "Transcribing" : "Stop dictation")
            .disabled(isTranscribing)
            .voiceBarProminentButton(tint: .red)
            .buttonBorderShape(.circle)
        }
        .barPadding()
        .voiceBarGlass(in: Capsule())
    }

    private var timeString: String {
        String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - Transcript

    private var transcriptCard: some View {
        VStack(spacing: 10) {
            TextField("", text: $transcribedText, axis: .vertical)
                .font(.system(size: 15, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: 8) {
                circularButton(systemImage: "xmark", accessibility: "Discard transcript", action: onCancel)
                circularButton(systemImage: "mic", accessibility: "Dictate again", action: onRestart)

                Spacer(minLength: 8)

                Button("Insert", action: onInsert)
                    .lineLimit(1)
                    .voiceBarButton()
                Button("Run", action: onRun)
                    .lineLimit(1)
                    .voiceBarProminentButton(tint: .green)
            }
        }
        .padding(12)
        .voiceBarGlass(in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - No speech

    private var noSpeechBar: some View {
        HStack(spacing: 12) {
            titleBlock("No speech detected")

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
            Button("Try Again", action: onRestart)
                .lineLimit(1)
                .voiceBarProminentButton(tint: .green)
        }
        .barPadding()
        .voiceBarGlass(in: Capsule())
    }

    // MARK: - Permission

    private var permissionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.slash")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.22), in: Circle())

            titleBlock("Microphone Access")

            Button("Open Settings", action: onOpenSettings)
                .lineLimit(1)
                .voiceBarProminentButton(tint: .green)
        }
        .barPadding()
        .voiceBarGlass(in: Capsule())
    }

    // MARK: - Status and error

    private func statusBar(title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
        }
        .barPadding()
        .voiceBarGlass(in: Capsule())
    }

    private func errorBar(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
        }
        .barPadding()
        .voiceBarGlass(in: Capsule())
    }

    // MARK: - Shared

    private func titleBlock(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circularButton(
        systemImage: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: Self.glyphBox, height: Self.glyphBox)
        }
        .accessibilityLabel(accessibility)
        .voiceBarButton()
        .buttonBorderShape(.circle)
    }
}

// MARK: - Level Meter

private struct LevelMeter: View {
    let level: Float

    @State private var history: [Float] = Array(repeating: 0, count: 22)

    private var scale: Float {
        max(history.max() ?? 0, 0.02)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 3, height: 3 + CGFloat(min(1, value / scale)) * 19)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 22)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.42)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .onChange(of: level) { _, newValue in
            history.removeFirst()
            history.append(newValue)
        }
    }
}

// MARK: - Native material helpers

private extension View {
    func barPadding() -> some View {
        padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    func voiceBarGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func voiceBarButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func voiceBarProminentButton(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent).tint(tint)
        } else {
            buttonStyle(.borderedProminent).tint(tint)
        }
    }
}
