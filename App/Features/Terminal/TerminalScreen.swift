import SwiftUI

struct TerminalScreen: View {
    let profile: SSHConnectionProfile
    let sshSession: SSHSession
    let onDisconnect: () -> Void

    @State private var terminalTitle: String = ""
    @State private var connectionState: ConnectionState = .disconnected
    @State private var showCommandPalette = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            TerminalViewRepresentable(
                sshSession: sshSession,
                terminalTitle: $terminalTitle
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if showCommandPalette {
                CommandPaletteView(
                    sshSession: sshSession,
                    onDismiss: { showCommandPalette = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    connectionIndicator
                    Text(terminalTitle.isEmpty ? "\(profile.username)@\(profile.host)" : terminalTitle)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showCommandPalette.toggle()
                        }
                    } label: {
                        Label("Command Palette", systemImage: "command")
                    }
                    Button(role: .destructive) {
                        Task {
                            await sshSession.disconnect()
                            onDisconnect()
                        }
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await observeConnectionState()
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch connectionState {
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .connecting, .reconnecting:
            ProgressView()
                .scaleEffect(0.6)
        case .disconnected:
            Circle()
                .fill(.red)
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
}

struct CommandPaletteView: View {
    let sshSession: SSHSession
    let onDismiss: () -> Void

    private let tmuxCommands: [(label: String, keys: String, bytes: [UInt8])] = [
        ("New Window", "c", [0x02, 0x63]),
        ("Next Window", "n", [0x02, 0x6E]),
        ("Prev Window", "p", [0x02, 0x70]),
        ("Split H", "\"", [0x02, 0x22]),
        ("Split V", "%", [0x02, 0x25]),
        ("Detach", "d", [0x02, 0x64]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Commands")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tmuxCommands, id: \.label) { cmd in
                        Button {
                            sendBytes(cmd.bytes)
                        } label: {
                            VStack(spacing: 2) {
                                Text(cmd.label)
                                    .font(.caption2.bold())
                                Text("^b \(cmd.keys)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        sendBytes([0x02, 0x5B])
                    } label: {
                        VStack(spacing: 2) {
                            Text("Copy Mode")
                                .font(.caption2.bold())
                            Text("^b [")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        Task {
            try? await sshSession.write(Data(bytes))
        }
    }
}
