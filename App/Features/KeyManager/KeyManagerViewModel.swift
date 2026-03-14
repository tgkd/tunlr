import Foundation

enum KeyManagerViewModelError: Error, Equatable {
    case keyNotFound
    case deletionFailed
}

@MainActor
class KeyManagerViewModel: ObservableObject {
    @Published var keys: [SSHIdentity] = []
    @Published var isGeneratingKey: Bool = false
    @Published var isImportingKey: Bool = false
    @Published var errorMessage: String?

    private let keyManager: KeyManager

    init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    func loadKeys() async {
        keys = await keyManager.listAllKeys()
    }

    func generateSecureEnclaveKey(label: String) async throws {
        isGeneratingKey = true
        defer { isGeneratingKey = false }
        let identity = try await keyManager.generateSecureEnclaveKey(label: label)
        keys.append(identity)
    }

    func importKey(pemData: Data, label: String, passphrase: String?) async throws {
        isImportingKey = true
        defer { isImportingKey = false }
        let identity = try await keyManager.importKey(pemData: pemData, label: label, passphrase: passphrase)
        keys.append(identity)
    }

    func deleteKey(_ identity: SSHIdentity) async {
        await keyManager.deleteKey(identity: identity)
        keys.removeAll { $0.id == identity.id }
    }

    func publicKeyString(for identity: SSHIdentity) -> String {
        switch identity.storageType {
        case .secureEnclave:
            return SecureEnclaveKeyManager.publicKeyOpenSSHFormat(
                publicKeyData: identity.publicKeyData,
                comment: identity.label
            )
        case .keychain:
            return formatImportedPublicKey(identity)
        }
    }

    private func formatImportedPublicKey(_ identity: SSHIdentity) -> String {
        var blob = Data()

        func appendSSHString(_ string: String) {
            var len = UInt32(string.utf8.count).bigEndian
            blob.append(Data(bytes: &len, count: 4))
            blob.append(Data(string.utf8))
        }

        func appendSSHData(_ data: Data) {
            var len = UInt32(data.count).bigEndian
            blob.append(Data(bytes: &len, count: 4))
            blob.append(data)
        }

        appendSSHString(identity.keyType)

        switch identity.keyType {
        case let k where k.hasPrefix("ecdsa-sha2-"):
            let curveName = String(k.dropFirst("ecdsa-sha2-".count))
            appendSSHString(curveName)
            appendSSHData(identity.publicKeyData)
        case "ssh-rsa":
            blob.append(identity.publicKeyData)
        default:
            appendSSHData(identity.publicKeyData)
        }

        let base64 = blob.base64EncodedString()
        return "\(identity.keyType) \(base64) \(identity.label)"
    }

    func keyTypeBadge(for identity: SSHIdentity) -> (label: String, icon: String) {
        switch identity.storageType {
        case .secureEnclave:
            return ("SE P-256", "cpu")
        case .keychain:
            switch identity.keyType {
            case "ssh-ed25519":
                return ("Ed25519", "key")
            case "ssh-rsa":
                return ("RSA", "key")
            case let type where type.hasPrefix("ecdsa-"):
                return ("ECDSA", "key")
            default:
                return (identity.keyType, "key")
            }
        }
    }
}
