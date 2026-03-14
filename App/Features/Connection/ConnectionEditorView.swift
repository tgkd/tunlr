import SwiftUI

struct ConnectionEditorView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    let existingProfile: SSHConnectionProfile?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var portString: String = "22"
    @State private var username: String = ""
    @State private var authSelection: AuthSelection = .password
    @State private var password: String = ""
    @State private var selectedKeyID: UUID?
    @State private var autoReconnect: Bool = false
    @State private var keepaliveIntervalString: String = "60"

    @State private var errorMessage: String?
    @State private var showingError: Bool = false

    enum AuthSelection: String, CaseIterable {
        case secureEnclaveKey = "Secure Enclave Key"
        case importedKey = "Imported Key"
        case password = "Password"
    }

    var isEditing: Bool { existingProfile != nil }

    var body: some View {
        Form {
            connectionSection
            authSection
            advancedSection
            testSection
        }
        .navigationTitle(isEditing ? "Edit Connection" : "New Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task {
            await viewModel.loadKeys()
            if let profile = existingProfile {
                loadProfile(profile)
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section("Connection") {
            TextField("Hostname or IP", text: $host)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            TextField("Port", text: $portString)
                .keyboardType(.numberPad)

            TextField("Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private var authSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $authSelection) {
                ForEach(AuthSelection.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }

            switch authSelection {
            case .secureEnclaveKey:
                seKeyPicker
            case .importedKey:
                importedKeyPicker
            case .password:
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            HStack {
                Text("Keepalive Interval")
                Spacer()
                TextField("seconds", text: $keepaliveIntervalString)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("s")
                    .foregroundStyle(.secondary)
            }
            Toggle("Auto-Reconnect", isOn: $autoReconnect)
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task {
                    let port = UInt16(portString) ?? 22
                    await viewModel.testConnection(host: host, port: port)
                }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if viewModel.isTestingConnection {
                        ProgressView()
                    } else if let result = viewModel.testConnectionResult {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTestingConnection)
        }
    }

    // MARK: - Key Pickers

    private var seKeyPicker: some View {
        let seKeys = viewModel.availableKeys.filter { $0.storageType == .secureEnclave }
        return Group {
            if seKeys.isEmpty {
                Text("No Secure Enclave keys available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Picker("Key", selection: $selectedKeyID) {
                    Text("Select a key").tag(nil as UUID?)
                    ForEach(seKeys) { key in
                        Text(key.label).tag(key.id as UUID?)
                    }
                }
            }
        }
    }

    private var importedKeyPicker: some View {
        let importedKeys = viewModel.availableKeys.filter { $0.storageType == .keychain }
        return Group {
            if importedKeys.isEmpty {
                Text("No imported keys available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Picker("Key", selection: $selectedKeyID) {
                    Text("Select a key").tag(nil as UUID?)
                    ForEach(importedKeys) { key in
                        HStack {
                            Text(key.label)
                            Text("(\(key.keyType))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(key.id as UUID?)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadProfile(_ profile: SSHConnectionProfile) {
        host = profile.host
        portString = String(profile.port)
        username = profile.username
        autoReconnect = profile.autoReconnect
        keepaliveIntervalString = String(Int(profile.keepaliveInterval))

        switch profile.authMethod {
        case .secureEnclaveKey(let keyTag):
            authSelection = .secureEnclaveKey
            selectedKeyID = UUID(uuidString: keyTag)
        case .importedKey(let keyID):
            authSelection = .importedKey
            selectedKeyID = keyID
        case .password:
            authSelection = .password
        }

        Task {
            if let pw = await viewModel.password(for: profile.id) {
                password = pw
            }
        }
    }

    private func save() {
        let port = UInt16(portString) ?? 22

        do {
            try viewModel.validateFields(host: host, username: username, port: port)
        } catch {
            errorMessage = describeError(error)
            showingError = true
            return
        }

        guard let authMethod = buildAuthMethod() else {
            errorMessage = "Please select an SSH key."
            showingError = true
            return
        }

        Task {
            do {
                let keepalive = TimeInterval(keepaliveIntervalString) ?? 60
                if var existing = existingProfile {
                    existing.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
                    existing.port = port
                    existing.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    existing.authMethod = authMethod
                    existing.autoReconnect = autoReconnect
                    existing.keepaliveInterval = keepalive
                    let pw = authSelection == .password ? password : nil
                    try await viewModel.updateProfile(existing, password: pw)
                } else {
                    let pw = authSelection == .password ? password : nil
                    try await viewModel.addProfile(
                        host: host,
                        port: port,
                        username: username,
                        authMethod: authMethod,
                        password: pw,
                        autoReconnect: autoReconnect,
                        keepaliveInterval: keepalive
                    )
                }
                onSave()
            } catch {
                errorMessage = describeError(error)
                showingError = true
            }
        }
    }

    private func buildAuthMethod() -> SSHAuthMethod? {
        switch authSelection {
        case .secureEnclaveKey:
            guard let keyID = selectedKeyID else { return nil }
            return .secureEnclaveKey(keyTag: keyID.uuidString)
        case .importedKey:
            guard let keyID = selectedKeyID else { return nil }
            return .importedKey(keyID: keyID)
        case .password:
            return .password
        }
    }

    private func describeError(_ error: Error) -> String {
        switch error {
        case ConnectionViewModelError.emptyHost:
            return "Hostname is required."
        case ConnectionViewModelError.emptyUsername:
            return "Username is required."
        case ConnectionViewModelError.invalidPort:
            return "Port must be between 1 and 65535."
        case ConnectionViewModelError.invalidHostFormat:
            return "Hostname contains invalid characters."
        case ConnectionViewModelError.invalidUsernameFormat:
            return "Username contains invalid characters."
        case ConnectionViewModelError.hostTooLong:
            return "Hostname is too long (max 253 characters)."
        case ConnectionViewModelError.usernameTooLong:
            return "Username is too long (max 128 characters)."
        default:
            return error.localizedDescription
        }
    }
}
