import SwiftUI

struct HostKeyMismatchWarning: View {
    let hostname: String
    let port: UInt16
    let existingFingerprint: String
    let newFingerprint: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("WARNING: HOST KEY CHANGED")
                .font(.title2.bold())
                .foregroundStyle(.red)

            Text("The host key for \(hostname):\(port) has changed. This could indicate a man-in-the-middle attack.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected Fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(existingFingerprint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Received Fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(newFingerprint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Text("If you did not expect this change, do not connect. Contact your server administrator.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                onDismiss()
                dismiss()
            } label: {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .interactiveDismissDisabled()
    }
}
