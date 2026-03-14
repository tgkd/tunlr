import Foundation
import CryptoKit
import Security

actor SecureEnclaveKeyManager {
    private static let keychainServiceName = "com.divinemarssh.se-keys"

    enum SecureEnclaveError: Error, Equatable {
        case secureEnclaveNotAvailable
        case keyNotFound
        case keychainError(OSStatus)
        case invalidKeyData
    }

    func generateKey(label: String) throws -> SSHIdentity {
        guard SecureEnclave.isAvailable else {
            throw SecureEnclaveError.secureEnclaveNotAvailable
        }

        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        )!

        let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
            accessControl: accessControl
        )

        let tag = UUID().uuidString
        try storeKeyData(privateKey.dataRepresentation, tag: tag)

        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.x963Representation

        return SSHIdentity(
            id: UUID(),
            label: label,
            keyType: "ecdsa-sha2-nistp256",
            publicKeyData: publicKeyData,
            createdAt: Date(),
            storageType: .secureEnclave
        )
    }

    func loadKey(tag: String) throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard let data = loadKeyData(tag: tag) else {
            throw SecureEnclaveError.keyNotFound
        }
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        } catch {
            throw SecureEnclaveError.invalidKeyData
        }
    }

    func deleteKey(tag: String) {
        deleteKeyData(tag: tag)
    }

    // MARK: - OpenSSH Format

    static func publicKeyOpenSSHFormat(publicKeyData: Data, comment: String = "") -> String {
        let blob = encodeSSHPublicKeyBlob(publicKeyData: publicKeyData)
        let base64 = blob.base64EncodedString()
        if comment.isEmpty {
            return "ecdsa-sha2-nistp256 \(base64)"
        }
        return "ecdsa-sha2-nistp256 \(base64) \(comment)"
    }

    static func encodeSSHPublicKeyBlob(publicKeyData: Data) -> Data {
        var blob = Data()
        let keyType = "ecdsa-sha2-nistp256"
        let curveName = "nistp256"

        sshEncodeString(keyType, into: &blob)
        sshEncodeString(curveName, into: &blob)
        sshEncodeData(publicKeyData, into: &blob)

        return blob
    }

    // MARK: - Signature Conversion (P1363 to DER)

    static func p1363ToDER(signature: Data) -> Data {
        let halfLen = signature.count / 2
        let r = signature.prefix(halfLen)
        let s = signature.suffix(halfLen)

        let derR = encodeASN1Integer(r)
        let derS = encodeASN1Integer(s)

        var der = Data()
        der.append(0x30) // SEQUENCE tag
        let seqLen = derR.count + derS.count
        der.append(contentsOf: encodeASN1Length(seqLen))
        der.append(derR)
        der.append(derS)

        return der
    }

    // MARK: - SSH Signature Blob

    static func encodeSSHSignatureBlob(derSignature: Data) -> Data {
        var blob = Data()
        sshEncodeString("ecdsa-sha2-nistp256", into: &blob)
        sshEncodeData(derSignature, into: &blob)
        return blob
    }

    // MARK: - Private Helpers

    private static func sshEncodeString(_ string: String, into data: inout Data) {
        let bytes = Data(string.utf8)
        sshEncodeData(bytes, into: &data)
    }

    private static func sshEncodeData(_ bytes: Data, into data: inout Data) {
        var length = UInt32(bytes.count).bigEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(bytes)
    }

    private static func encodeASN1Integer(_ value: Data) -> Data {
        var bytes = Array(value)

        // Remove leading zeros but keep one if the value is zero
        while bytes.count > 1 && bytes[0] == 0 {
            bytes.removeFirst()
        }

        // Add leading zero if high bit is set (to keep it positive)
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }

        var result = Data()
        result.append(0x02) // INTEGER tag
        result.append(contentsOf: encodeASN1Length(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }

    private static func encodeASN1Length(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else if length < 256 {
            return [0x81, UInt8(length)]
        } else {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        }
    }

    // MARK: - Keychain Storage

    private func storeKeyData(_ data: Data, tag: String) throws {
        deleteKeyData(tag: tag)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveError.keychainError(status)
        }
    }

    private func loadKeyData(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    private func deleteKeyData(tag: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: tag,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
