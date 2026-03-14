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
        let keyTypeBytes = Data(identity.keyType.utf8)
        var keyTypeLen = UInt32(keyTypeBytes.count).bigEndian
        blob.append(Data(bytes: &keyTypeLen, count: 4))
        blob.append(keyTypeBytes)

        var pubKeyLen = UInt32(identity.publicKeyData.count).bigEndian
        blob.append(Data(bytes: &pubKeyLen, count: 4))
        blob.append(identity.publicKeyData)

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
