import Foundation
import CryptoKit
import Security

struct ImportedKeyAuthenticator: SSHAuthenticatable {
    let keyID: UUID
    let manager: KeychainKeyManager

    func authenticate(sessionHash: Data) async throws -> Data {
        let rawData = try await manager.loadKey(id: keyID)
        let stored = try JSONDecoder().decode(StoredKeyData.self, from: rawData)
        return try sign(sessionHash: sessionHash, keyData: stored)
    }

    private func sign(sessionHash: Data, keyData: StoredKeyData) throws -> Data {
        switch keyData.keyType {
        case "ssh-ed25519":
            return try signEd25519(sessionHash: sessionHash, privateKeyBytes: keyData.privateKeyBytes)
        case let k where k.hasPrefix("ecdsa-sha2-"):
            return try signECDSA(sessionHash: sessionHash, privateKeyBytes: keyData.privateKeyBytes)
        case "ssh-rsa":
            return try signRSA(sessionHash: sessionHash, privateKeyData: keyData.privateKeyBytes)
        default:
            throw ImportedKeyError.unsupportedKeyType(keyData.keyType)
        }
    }

    private func signEd25519(sessionHash: Data, privateKeyBytes: Data) throws -> Data {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
        let signature = try privateKey.signature(for: sessionHash)
        return encodeSSHSignatureBlob(algorithm: "ssh-ed25519", signature: signature)
    }

    private func signECDSA(sessionHash: Data, privateKeyBytes: Data) throws -> Data {
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
        let signature = try privateKey.signature(for: sessionHash)
        let der = SecureEnclaveKeyManager.p1363ToDER(signature: signature.rawRepresentation)
        return SecureEnclaveKeyManager.encodeSSHSignatureBlob(derSignature: der)
    }

    private func signRSA(sessionHash: Data, privateKeyData: Data) throws -> Data {
        let components = try JSONDecoder().decode(RSAKeyComponents.self, from: privateKeyData)
        let secKey = try createRSASecKey(components: components)

        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            sessionHash as CFData,
            &error
        ) as Data? else {
            throw ImportedKeyError.signingFailed
        }
        return encodeSSHSignatureBlob(algorithm: "rsa-sha2-256", signature: signatureData)
    }

    private func createRSASecKey(components: RSAKeyComponents) throws -> SecKey {
        var keyBytes = [UInt8]()
        // PKCS#1 RSAPrivateKey DER encoding
        keyBytes.append(0x30) // SEQUENCE
        var innerBytes = [UInt8]()
        appendASN1Integer(Data([0x00]), to: &innerBytes) // version
        appendASN1Integer(components.n, to: &innerBytes)
        appendASN1Integer(components.e, to: &innerBytes)
        appendASN1Integer(components.d, to: &innerBytes)
        appendASN1Integer(components.p, to: &innerBytes)
        appendASN1Integer(components.q, to: &innerBytes)
        appendASN1Integer(components.dp, to: &innerBytes)
        appendASN1Integer(components.dq, to: &innerBytes)
        appendASN1Integer(components.iqmp, to: &innerBytes)
        keyBytes.append(contentsOf: encodeASN1Length(innerBytes.count))
        keyBytes.append(contentsOf: innerBytes)

        let keyData = Data(keyBytes)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: components.n.drop(while: { $0 == 0 }).count * 8,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw ImportedKeyError.signingFailed
        }
        return secKey
    }

    private func appendASN1Integer(_ value: Data, to data: inout [UInt8]) {
        var bytes = Array(value)
        while bytes.count > 1 && bytes[0] == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        data.append(0x02) // INTEGER
        data.append(contentsOf: encodeASN1Length(bytes.count))
        data.append(contentsOf: bytes)
    }

    private func encodeASN1Length(_ length: Int) -> [UInt8] {
        if length < 128 { return [UInt8(length)] }
        if length < 256 { return [0x81, UInt8(length)] }
        return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
    }

    private func encodeSSHSignatureBlob(algorithm: String, signature: Data) -> Data {
        var blob = Data()
        var length = UInt32(algorithm.utf8.count).bigEndian
        blob.append(Data(bytes: &length, count: 4))
        blob.append(Data(algorithm.utf8))
        var sigLength = UInt32(signature.count).bigEndian
        blob.append(Data(bytes: &sigLength, count: 4))
        blob.append(signature)
        return blob
    }

    enum ImportedKeyError: Error, Equatable {
        case unsupportedKeyType(String)
        case signingFailed
    }
}
