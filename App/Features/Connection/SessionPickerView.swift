import SwiftUI

struct SessionPickerView: View {
    let choice: RemoteSessionChoice
    let creatableBackends: [SessionBackendKind]
    let onSelect: (RemoteSessionEntry?) -> Void
    let onCreate: (SessionBackendKind, String) -> Void
    let onCancel: () -> Void

    @State private var newSessionName: String = ""
    @State private var newSessionBackend: SessionBackendKind?

    private var trimmedNewSessionName: String {
        newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedNewSessionBackend: SessionBackendKind? {
        if let newSessionBackend, creatableBackends.contains(newSessionBackend) {
            return newSessionBackend
        }
        return creatableBackends.first
    }

    private var backendsWithEntries: [SessionBackendKind] {
        SessionBackendKind.allCases.filter { backend in
            choice.entries.contains { $0.backend == backend }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let missingName = choice.missingName {
                    Section {
                        Label("“\(missingName)” is no longer running.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(backendsWithEntries, id: \.self) { backend in
                    Section {
                        ForEach(choice.entries.filter { $0.backend == backend }) { entry in
                            SessionPickerEntryRow(entry: entry) {
                                onSelect(entry)
                            }
                        }
                    } header: {
                        SessionPickerBackendHeader(backend: backend)
                    }
                }

                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("Plain shell", systemImage: "terminal")
                    }
                }

                if !creatableBackends.isEmpty {
                    newSessionSection
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    private var newSessionSection: some View {
        Section("New session") {
            TextField("Session name", text: $newSessionName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { create() }

            if creatableBackends.count > 1 {
                Picker("Backend", selection: Binding(
                    get: { resolvedNewSessionBackend ?? creatableBackends[0] },
                    set: { newSessionBackend = $0 }
                )) {
                    ForEach(creatableBackends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button("Create") { create() }
                .disabled(trimmedNewSessionName.isEmpty)
        }
    }

    private func create() {
        let name = trimmedNewSessionName
        guard !name.isEmpty, let backend = resolvedNewSessionBackend else {
            return
        }
        onCreate(backend, name)
    }
}

private struct SessionPickerBackendHeader: View {
    let backend: SessionBackendKind

    var body: some View {
        HStack(spacing: 6) {
            Text(backend.displayName)
            if backend.isExperimental {
                Text("Experimental")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SessionPickerEntryRow: View {
    let entry: RemoteSessionEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundStyle(.primary)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}
