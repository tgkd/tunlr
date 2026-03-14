import SwiftUI

struct HostVerificationSheet: View {
    let request: HostKeyVerificationRequest
    let onTrust: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Verify Host Key")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Host", value: "\(request.hostname):\(request.port)")
                    .font(.body.monospaced())
                LabeledContent("Key Type", value: request.keyType)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fingerprint")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(request.fingerprint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("This is the first time connecting to this host. Verify the fingerprint matches the server's key before trusting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onTrust()
                    dismiss()
                } label: {
                    Text("Trust & Connect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
