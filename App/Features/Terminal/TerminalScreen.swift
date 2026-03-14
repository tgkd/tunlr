import SwiftUI

struct TerminalScreen: View {
    let profile: SSHConnectionProfile
    let sshSession: SSHSession
    let onDisconnect: () -> Void

    @State private var terminalTitle: String = ""
    @State private var connectionState: ConnectionState = .disconnected
    @State private var showCommandPalette = false
    @State private var showDisconnectAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            TerminalViewRepresentable(
                sshSession: sshSession,
                terminalTitle: $terminalTitle
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if showCommandPalette {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showCommandPalette = false
                        }
                    }

                CommandPaletteView(
                    sshSession: sshSession,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showCommandPalette = false
                        }
                    }
                )
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
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
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCommandPalette.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(colorScheme == .dark ? Color.black : Color(white: 0.97), for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
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
        .task {
            await observeConnectionState()
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
}

struct CommandPaletteView: View {
    let sshSession: SSHSession
    let onDismiss: () -> Void

    private let tmuxCommands: [(label: String, icon: String, keys: String, bytes: [UInt8])] = [
        ("New Window", "plus.rectangle", "c", [0x02, 0x63]),
        ("Next Window", "chevron.right", "n", [0x02, 0x6E]),
        ("Prev Window", "chevron.left", "p", [0x02, 0x70]),
        ("Split H", "rectangle.split.1x2", "\"", [0x02, 0x22]),
        ("Split V", "rectangle.split.2x1", "%", [0x02, 0x25]),
        ("Copy Mode", "doc.on.doc", "[", [0x02, 0x5B]),
        ("Detach", "eject", "d", [0x02, 0x64]),
    ]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("tmux")
                    .font(.footnote.bold().monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray4))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                ForEach(tmuxCommands, id: \.label) { cmd in
                    Button {
                        sendBytes(cmd.bytes)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cmd.icon)
                                .font(.system(size: 16))
                            Text(cmd.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("^b \(cmd.keys)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        Task {
            try? await sshSession.write(Data(bytes))
        }
    }
}
