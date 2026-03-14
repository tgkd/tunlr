import SwiftUI
import CoreImage.CIFilterBuiltins

struct ScreenshotProtectionModifier: ViewModifier {
    @State private var isCaptured = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isCaptured ? 0 : 1)

            if isCaptured {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash.fill")
                        .font(.largeTitle)
                    Text("Content hidden during screen capture")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isCaptured = UIScreen.main.isCaptured
        }
        .onAppear {
            isCaptured = UIScreen.main.isCaptured
        }
    }
}

extension View {
    func screenshotProtected() -> some View {
        modifier(ScreenshotProtectionModifier())
    }
}

struct KeyManagerView: View {
    @ObservedObject var viewModel: KeyManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false
    @State private var selectedIdentity: SSHIdentity?
    @State private var showingDeleteConfirmation = false
    @State private var identityToDelete: SSHIdentity?

    var body: some View {
        List {
            if viewModel.keys.isEmpty {
                ContentUnavailableView(
                    "No Keys",
                    systemImage: "key",
                    description: Text("Tap + to generate or import an SSH key.")
                )
            } else {
                ForEach(viewModel.keys) { identity in
                    KeyRow(identity: identity, viewModel: viewModel)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIdentity = identity
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                identityToDelete = identity
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("SSH Keys")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                AddKeyView(viewModel: viewModel, onDone: {
                    showingAddSheet = false
                })
            }
        }
        .sheet(item: $selectedIdentity) { identity in
            NavigationStack {
                KeyDetailView(identity: identity, viewModel: viewModel)
            }
        }
        .alert("Delete Key?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let identity = identityToDelete {
                    Task {
                        await viewModel.deleteKey(identity)
                    }
                }
            }
        } message: {
            if let identity = identityToDelete {
                Text("This will permanently delete \"\(identity.label)\". This action cannot be undone.")
            }
        }
        .task {
            await viewModel.loadKeys()
        }
        .screenshotProtected()
    }
}

struct KeyRow: View {
    let identity: SSHIdentity
    let viewModel: KeyManagerViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(identity.label)
                    .font(.body)
                Text(identity.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            keyTypeBadge
        }
        .padding(.vertical, 2)
    }

    private var keyTypeBadge: some View {
        let badge = viewModel.keyTypeBadge(for: identity)
        return Label(badge.label, systemImage: badge.icon)
            .font(.caption2)
            .foregroundStyle(identity.storageType == .secureEnclave ? .blue : .green)
    }
}

struct AddKeyView: View {
    @ObservedObject var viewModel: KeyManagerViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddKeyMode = .secureEnclave
    @State private var label: String = ""
    @State private var pemText: String = ""
    @State private var passphrase: String = ""
    @State private var showingDocumentPicker = false
    @State private var errorMessage: String?
    @State private var showingError = false

    enum AddKeyMode: String, CaseIterable {
        case secureEnclave = "Secure Enclave"
        case importPEM = "Import Key"
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $mode) {
                    ForEach(AddKeyMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Label") {
                TextField("Key name", text: $label)
                    .autocorrectionDisabled()
            }

            if mode == .importPEM {
                Section("Private Key (PEM)") {
                    TextEditor(text: $pemText)
                        .font(.caption.monospaced())
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Passphrase (optional)") {
                    SecureField("Passphrase", text: $passphrase)
                }
            }
        }
        .navigationTitle("Add Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { addKey() }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (mode == .importPEM && pemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                              viewModel.isGeneratingKey || viewModel.isImportingKey)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func addKey() {
        Task {
            do {
                switch mode {
                case .secureEnclave:
                    try await viewModel.generateSecureEnclaveKey(
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                case .importPEM:
                    guard let pemData = pemText.data(using: .utf8) else {
                        errorMessage = "Invalid PEM data"
                        showingError = true
                        return
                    }
                    let pass = passphrase.isEmpty ? nil : passphrase
                    try await viewModel.importKey(
                        pemData: pemData,
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                        passphrase: pass
                    )
                }
                onDone()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
