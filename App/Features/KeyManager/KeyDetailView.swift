import SwiftUI
import CoreImage.CIFilterBuiltins

struct KeyDetailView: View {
    let identity: SSHIdentity
    let viewModel: KeyManagerViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        List {
            Section("Key Info") {
                LabeledContent("Label", value: identity.label)
                LabeledContent("Type", value: identity.keyType)
                LabeledContent("Storage", value: identity.storageType == .secureEnclave ? "Secure Enclave" : "Keychain")
                LabeledContent("Created", value: identity.createdAt, format: .dateTime)
            }

            Section("Fingerprint") {
                let fingerprint = FingerprintFormatter.sha256Fingerprint(of: identity.publicKeyData)
                Text(fingerprint)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Public Key (authorized_keys)") {
                let pubKeyString = viewModel.publicKeyString(for: identity)
                Text(pubKeyString)
                    .font(.caption2.monospaced())
                    .lineLimit(6)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = pubKeyString
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    HStack {
                        Text(copied ? "Copied" : "Copy to Clipboard")
                        Spacer()
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }

            Section("QR Code") {
                let pubKeyString = viewModel.publicKeyString(for: identity)
                if let qrImage = generateQRCode(from: pubKeyString) {
                    HStack {
                        Spacer()
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                        Spacer()
                    }
                } else {
                    Text("Unable to generate QR code")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Key Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .screenshotProtected()
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
