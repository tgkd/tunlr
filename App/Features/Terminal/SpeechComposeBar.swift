import SwiftUI

struct SpeechComposeBar: View {
    let state: WhisperServiceState
    @Binding var transcribedText: String
    let onSend: () -> Void
    let onRun: () -> Void
    let onCancel: () -> Void
    let onStopRecording: () -> Void

    var body: some View {
        Group {
            switch state {
            case .recording:
                recordingBar
            case .transcribing:
                transcribingBar
            case .downloading:
                downloadingBar
            case .error(let message):
                errorBar(message: message)
            default:
                reviewBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Recording

    private var recordingBar: some View {
        HStack(spacing: 12) {
            DictationDots()

            Text("Dictating...")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            dismissButton

            Button {
                onStopRecording()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.red, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(white: 0.15))
        )
    }

    // MARK: - Transcribing

    private var transcribingBar: some View {
        HStack(spacing: 12) {
            WaveformIcon()

            Text("Transcribing...")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            dismissButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(white: 0.15))
        )
    }

    // MARK: - Downloading

    private var downloadingBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text("Downloading model...")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            dismissButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(white: 0.15))
        )
    }

    // MARK: - Error

    private func errorBar(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))

            Text(message)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            dismissButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(white: 0.15))
        )
    }

    // MARK: - Review

    private var reviewBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $transcribedText, axis: .vertical)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.green, lineWidth: 1.5)
                )

            dismissButton

            Button {
                onRun()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.green, in: Circle())
            }
        }
    }

    // MARK: - Shared

    private var dismissButton: some View {
        Button {
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.15), in: Circle())
        }
    }
}

// MARK: - Animated Dictation Dots

private struct DictationDots: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                    .opacity(active ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Waveform Icon

private struct WaveformIcon: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(zip([0,1,2,3], [0.6, 0.3, 0.5, 0.15] as [Double])), id: \.0) { index, delay in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white)
                    .frame(width: 3, height: active ? heights1[index] : heights2[index])
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(delay),
                        value: active
                    )
            }
        }
        .frame(height: 16)
        .onAppear { active = true }
    }

    private let heights1: [CGFloat] = [12, 6, 14, 8]
    private let heights2: [CGFloat] = [6, 14, 8, 12]
}
