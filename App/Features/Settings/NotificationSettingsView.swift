import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: AppearanceViewModel
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
    @State private var copiedSnippet: String?

    var body: some View {
        Form {
            Section {
                Toggle("Haptic", isOn: bellBinding(\.haptic))
                Toggle("Sound", isOn: bellBinding(\.sound))
                Toggle("Screen Flash", isOn: bellBinding(\.flash))
                Toggle("Push Notification", isOn: bellPushBinding)
            } header: {
                Text("Bell")
            } footer: {
                Text("Triggered when a program sends BEL (Ctrl-G). No setup needed.")
            }

            Section {
                Toggle("Haptic", isOn: commandFinishedBinding(\.haptic))
                Toggle("Sound", isOn: commandFinishedBinding(\.sound))
                Toggle("Screen Flash", isOn: commandFinishedBinding(\.flash))
                Toggle("Push Notification", isOn: commandFinishedPushBinding)
            } header: {
                Text("Command Finished")
            } footer: {
                Text("Notifies when a command finishes with success or failure. Requires shell integration on the remote server (see below).")
            }

            shellIntegrationSection

            Section {
                Toggle("Haptic", isOn: shellNotificationBinding(\.haptic))
                Toggle("Sound", isOn: shellNotificationBinding(\.sound))
                Toggle("Screen Flash", isOn: shellNotificationBinding(\.flash))
                Toggle("Push Notification", isOn: shellNotificationPushBinding)
            } header: {
                Text("Shell Notifications")
            } footer: {
                Text("Triggered by scripts using:\nprintf '\\e]777;notify;Title;Body\\a'")
            }

            if notificationPermission == .denied {
                Section {
                    Button("Open Settings to Enable Notifications") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("Push notifications are disabled. Enable them in system Settings.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkPermission()
        }
    }

    // MARK: - Shell Integration

    private static let zshSnippet = """
    precmd()  { printf '\\e]133;D;%s\\a\\e]133;A\\a' "$?" }
    preexec() { printf '\\e]133;B\\a' }
    """

    private static let bashSnippet = """
    PS0=$'\\e]133;B\\a'
    PROMPT_COMMAND='printf "\\e]133;D;%s\\a\\e]133;A\\a" "$?"'
    """

    @ViewBuilder
    private var shellIntegrationSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = Self.zshSnippet
                showCopied("zsh")
            } label: {
                HStack {
                    Label("Copy zsh snippet", systemImage: "doc.on.doc")
                    Spacer()
                    if copiedSnippet == "zsh" {
                        Text("Copied")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                UIPasteboard.general.string = Self.bashSnippet
                showCopied("bash")
            } label: {
                HStack {
                    Label("Copy bash snippet", systemImage: "doc.on.doc")
                    Spacer()
                    if copiedSnippet == "bash" {
                        Text("Copied")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Shell Integration Setup")
        } footer: {
            Text("Add the snippet to ~/.zshrc or ~/.bashrc on the remote server, then run \"source ~/.zshrc\" (or reconnect).")
        }
    }

    private func showCopied(_ shell: String) {
        withAnimation { copiedSnippet = shell }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { copiedSnippet = nil }
        }
    }

    // MARK: - Bindings

    private func bellBinding(_ keyPath: WritableKeyPath<EventNotificationConfig, Bool>) -> Binding<Bool> {
        configBinding(\.bell, keyPath)
    }

    private func commandFinishedBinding(_ keyPath: WritableKeyPath<EventNotificationConfig, Bool>) -> Binding<Bool> {
        configBinding(\.commandFinished, keyPath)
    }

    private func shellNotificationBinding(_ keyPath: WritableKeyPath<EventNotificationConfig, Bool>) -> Binding<Bool> {
        configBinding(\.shellNotification, keyPath)
    }

    private func configBinding(
        _ eventKeyPath: WritableKeyPath<EventNotificationSettings, EventNotificationConfig>,
        _ configKeyPath: WritableKeyPath<EventNotificationConfig, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.appearance.eventNotifications[keyPath: eventKeyPath][keyPath: configKeyPath] },
            set: { newValue in
                var updated = viewModel.appearance
                updated.eventNotifications[keyPath: eventKeyPath][keyPath: configKeyPath] = newValue
                Task { await viewModel.update(updated) }
            }
        )
    }

    private var bellPushBinding: Binding<Bool> { pushBinding(\.bell) }
    private var commandFinishedPushBinding: Binding<Bool> { pushBinding(\.commandFinished) }
    private var shellNotificationPushBinding: Binding<Bool> { pushBinding(\.shellNotification) }

    private func pushBinding(_ eventKeyPath: WritableKeyPath<EventNotificationSettings, EventNotificationConfig>) -> Binding<Bool> {
        Binding(
            get: { viewModel.appearance.eventNotifications[keyPath: eventKeyPath].pushNotification },
            set: { newValue in
                if newValue {
                    TerminalEventReactor.requestNotificationPermissionIfNeeded()
                }
                var updated = viewModel.appearance
                updated.eventNotifications[keyPath: eventKeyPath].pushNotification = newValue
                Task { await viewModel.update(updated) }
            }
        )
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus
    }
}
