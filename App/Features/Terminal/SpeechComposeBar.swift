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

    private var isRecording: Bool { state == .recording }

    var body: some View {
        Group {
            switch state {
            case .recording:
                dictatingBar
            case .transcribing:
                transcribingBar
            case .downloading:
                statusBar(title: "Downloading model...", showsSpinner: true)
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
            elapsed = 0
            guard isRecording else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsed += 1
            }
        }
    }

    // MARK: - Dictating

    private var dictatingBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Dictating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeString)
                    .font(.system(size: 17, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            LevelMeter(level: level)

            circularButton(systemImage: "xmark", accessibility: "Cancel dictation", action: onCancel)

            Button(action: onStopRecording) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                    .frame(width: 15, height: 15)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Stop dictation")
            .voiceBarProminentButton(tint: .red)
            .buttonBorderShape(.circle)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 56)
        .voiceBarGlass(in: Capsule())
    }

    private var timeString: String {
        String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - Transcribing

    private var transcribingBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Transcribing...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.green)
            }

            circularButton(systemImage: "xmark", accessibility: "Cancel", action: onCancel)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 56)
        .voiceBarGlass(in: Capsule())
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
                .frame(minHeight: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )

            HStack(spacing: 8) {
                circularButton(systemImage: "xmark", accessibility: "Discard transcript", action: onCancel)
                circularButton(systemImage: "mic", accessibility: "Dictate again", action: onRestart)

                Spacer(minLength: 0)

                Button("Insert", action: onInsert)
                    .voiceBarButton()
                Button("Run", action: onRun)
                    .voiceBarProminentButton(tint: .green)
            }
        }
        .padding(12)
        .voiceBarGlass(in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - No speech

    private var noSpeechBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("No speech detected")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Nothing was recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
            Button("Try Again", action: onRestart)
                .voiceBarProminentButton(tint: .green)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 64)
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

            VStack(alignment: .leading, spacing: 1) {
                Text("Microphone Access")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Needed for voice input.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Open Settings", action: onOpenSettings)
                .voiceBarProminentButton(tint: .green)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
        .frame(minHeight: 64)
        .voiceBarGlass(in: Capsule())
    }

    // MARK: - Status and error

    private func statusBar(title: String, showsSpinner: Bool) -> some View {
        HStack(spacing: 12) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 56)
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
                .lineLimit(2)

            Spacer(minLength: 0)

            circularButton(systemImage: "xmark", accessibility: "Dismiss", action: onCancel)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
        .voiceBarGlass(in: Capsule())
    }

    // MARK: - Shared

    private func circularButton(
        systemImage: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(accessibility)
        .voiceBarButton()
        .buttonBorderShape(.circle)
    }
}

// MARK: - Level Meter

private struct LevelMeter: View {
    let level: Float

    @State private var history: [Float] = Array(repeating: 0, count: 24)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 3, height: max(4, CGFloat(value) * 30))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 30)
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
