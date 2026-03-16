import SwiftUI

struct GettingStartedView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Getting Started")
                        .font(.title2.bold())
                    Text("How to set up your first SSH connection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                StepRow(
                    number: 1,
                    title: "Create an SSH Key",
                    icon: "key",
                    detail: "Go to Settings > SSH Keys and tap + to generate a Secure Enclave key. This creates a hardware-backed key protected by Face ID / Touch ID."
                )
                StepRow(
                    number: 2,
                    title: "Copy Your Public Key",
                    icon: "doc.on.doc",
                    detail: "Tap the key you just created, then copy the public key. It looks like: ecdsa-sha2-nistp256 AAAA..."
                )
                StepRow(
                    number: 3,
                    title: "Add Key to Your Server",
                    icon: "server.rack",
                    detail: "On your server, append the public key to ~/.ssh/authorized_keys:"
                )
                CodeBlock(text: "echo 'YOUR_PUBLIC_KEY' >> ~/.ssh/authorized_keys")
                StepRow(
                    number: 4,
                    title: "Add a Connection",
                    icon: "plus.circle",
                    detail: "Back in tunlr, tap + on the Connections screen. Enter the host, port (default 22), username, and select your key."
                )
                StepRow(
                    number: 5,
                    title: "Connect",
                    icon: "bolt.fill",
                    detail: "Tap the connection to start your SSH session. Authenticate with Face ID when prompted."
                )
            } header: {
                Text("Quick Start")
            }

            Section {
                AuthMethodRow(
                    title: "Secure Enclave Key",
                    icon: "cpu",
                    recommended: true,
                    detail: "Hardware-backed P-256 key. Private key never leaves the device. Protected by biometrics. Most secure option."
                )
                AuthMethodRow(
                    title: "Imported Key",
                    icon: "key",
                    recommended: false,
                    detail: "Import an existing Ed25519 or P-256 key file. Stored encrypted in Keychain. Use this if your server already has your key."
                )
                AuthMethodRow(
                    title: "Password",
                    icon: "lock",
                    recommended: false,
                    detail: "Stored securely in Keychain with biometric protection. Less secure than key-based authentication."
                )
            } header: {
                Text("Authentication Methods")
            }

            Section {
                TipRow(
                    icon: "arrow.clockwise",
                    title: "Auto-Reconnect",
                    detail: "Enable in connection settings to automatically reconnect when the app returns from background."
                )
                TipRow(
                    icon: "keyboard",
                    title: "Keyboard Shortcuts",
                    detail: "The toolbar above the keyboard has Ctrl, Alt, Esc, Tab, and arrows. Hold Ctrl and type to send control sequences (e.g. Ctrl+C)."
                )
                TipRow(
                    icon: "mic",
                    title: "Voice Input",
                    detail: "Tap the microphone button to dictate terminal commands. Speech is processed entirely on-device."
                )
                TipRow(
                    icon: "qrcode.viewfinder",
                    title: "Host Key Verification",
                    detail: "On first connect, tunlr saves the server's host key (Trust on First Use). You can also scan a QR code to verify the fingerprint."
                )
            } header: {
                Text("Tips")
            }
        }
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let icon: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .listRowInsets(EdgeInsets(top: 0, leading: 52, bottom: 8, trailing: 16))
    }
}

private struct AuthMethodRow: View {
    let title: String
    let icon: String
    let recommended: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.bold())
                if recommended {
                    Text("Recommended")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green))
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TipRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
