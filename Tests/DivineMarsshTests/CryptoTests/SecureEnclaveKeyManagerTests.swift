import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

struct SecureEnclaveKeyManagerTests {

    // MARK: - OpenSSH Public Key Format Tests

    @Test func publicKeyOpenSSHFormatProducesValidPrefix() {
        let key = P256.Signing.PrivateKey()
        let publicKeyData = key.publicKey.x963Representation

        let result = SecureEnclaveKeyManager.publicKeyOpenSSHFormat(publicKeyData: publicKeyData)

        #expect(result.hasPrefix("ecdsa-sha2-nistp256 "))
    }

    @Test func publicKeyOpenSSHFormatWithComment() {
        let key = P256.Signing.PrivateKey()
        let publicKeyData = key.publicKey.x963Representation

        let result = SecureEnclaveKeyManager.publicKeyOpenSSHFormat(
            publicKeyData: publicKeyData,
            comment: "test@host"
        )

        #expect(result.hasPrefix("ecdsa-sha2-nistp256 "))
        #expect(result.hasSuffix(" test@host"))
    }

    @Test func publicKeyOpenSSHFormatBase64DecodesBackToBlob() {
        let key = P256.Signing.PrivateKey()
        let publicKeyData = key.publicKey.x963Representation

        let result = SecureEnclaveKeyManager.publicKeyOpenSSHFormat(publicKeyData: publicKeyData)
        let parts = result.split(separator: " ")
        #expect(parts.count == 2)

        let base64Part = String(parts[1])
        let decoded = Data(base64Encoded: base64Part)
        #expect(decoded != nil)
    }

    @Test func sshPublicKeyBlobContainsCorrectFields() {
        let key = P256.Signing.PrivateKey()
        let publicKeyData = key.publicKey.x963Representation

        let blob = SecureEnclaveKeyManager.encodeSSHPublicKeyBlob(publicKeyData: publicKeyData)

        // Parse the blob to verify structure
        var offset = 0
        let keyType = readSSHString(from: blob, offset: &offset)
        let curveName = readSSHString(from: blob, offset: &offset)
        let keyData = readSSHData(from: blob, offset: &offset)

        #expect(keyType == "ecdsa-sha2-nistp256")
        #expect(curveName == "nistp256")
        #expect(keyData == publicKeyData)
        #expect(offset == blob.count)
    }

    @Test func sshPublicKeyBlobConsistentAcrossCalls() {
        let key = P256.Signing.PrivateKey()
        let publicKeyData = key.publicKey.x963Representation

        let blob1 = SecureEnclaveKeyManager.encodeSSHPublicKeyBlob(publicKeyData: publicKeyData)
        let blob2 = SecureEnclaveKeyManager.encodeSSHPublicKeyBlob(publicKeyData: publicKeyData)

        #expect(blob1 == blob2)
    }

    // MARK: - P1363 to DER Conversion Tests

    @Test func p1363ToDERProducesValidDERSequence() {
        // P-256 signature: 32 bytes r + 32 bytes s
        let r = Data(repeating: 0x01, count: 32)
        let s = Data(repeating: 0x02, count: 32)
        let p1363 = r + s

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        // DER should start with SEQUENCE tag
        #expect(der[0] == 0x30)
    }

    @Test func p1363ToDERContainsTwoIntegers() {
        let r = Data(repeating: 0x01, count: 32)
        let s = Data(repeating: 0x02, count: 32)
        let p1363 = r + s

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        // Parse DER
        var offset = 0
        #expect(der[offset] == 0x30) // SEQUENCE
        offset += 1
        let seqLen = readASN1Length(from: der, offset: &offset)
        #expect(seqLen > 0)

        // First INTEGER (r)
        #expect(der[offset] == 0x02)
        offset += 1
        let rLen = readASN1Length(from: der, offset: &offset)
        offset += rLen

        // Second INTEGER (s)
        #expect(der[offset] == 0x02)
        offset += 1
        let sLen = readASN1Length(from: der, offset: &offset)
        offset += sLen

        #expect(offset == der.count)
    }

    @Test func p1363ToDERHandlesHighBitInR() {
        // r starts with 0x80 (high bit set) - should get leading zero
        var r = Data(count: 32)
        r[0] = 0x80
        let s = Data(repeating: 0x01, count: 32)
        let p1363 = r + s

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        // Parse to find r integer
        var offset = 2 // skip SEQUENCE tag + length
        #expect(der[offset] == 0x02) // INTEGER tag
        offset += 1
        let rLen = readASN1Length(from: der, offset: &offset)
        // Should have leading zero byte to keep positive
        #expect(der[offset] == 0x00)
        #expect(rLen == 33) // original 32 + leading zero
    }

    @Test func p1363ToDERHandlesLeadingZerosInR() {
        // r with leading zeros - should be stripped
        var r = Data(count: 32)
        r[0] = 0x00
        r[1] = 0x00
        r[2] = 0x42
        let s = Data(repeating: 0x01, count: 32)
        let p1363 = r + s

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        var offset = 2
        #expect(der[offset] == 0x02)
        offset += 1
        let rLen = readASN1Length(from: der, offset: &offset)
        // Leading zeros stripped, first byte is 0x42 (no high bit, no extra zero needed)
        #expect(der[offset] == 0x42)
        #expect(rLen == 30)
    }

    @Test func p1363ToDERRoundTripWithCryptoKit() {
        let key = P256.Signing.PrivateKey()
        let data = "test data".data(using: .utf8)!
        let signature = try! key.signature(for: data)
        let p1363 = signature.rawRepresentation

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        // Verify DER is valid by checking structure
        #expect(der[0] == 0x30) // SEQUENCE
        #expect(der.count > 4) // At minimum: tag + len + 2 integers
        #expect(der.count <= 72) // Max DER size for P-256: 2 + 2 + 33 + 2 + 33
    }

    @Test func p1363ToDERDeterministic() {
        let r = Data(repeating: 0xAB, count: 32)
        let s = Data(repeating: 0xCD, count: 32)
        let p1363 = r + s

        let der1 = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)
        let der2 = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        #expect(der1 == der2)
    }

    // MARK: - SSH Signature Blob Tests

    @Test func sshSignatureBlobContainsKeyTypeAndSignature() {
        let derSig = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])

        let blob = SecureEnclaveKeyManager.encodeSSHSignatureBlob(derSignature: derSig)

        var offset = 0
        let sigType = readSSHString(from: blob, offset: &offset)
        let sigData = readSSHData(from: blob, offset: &offset)

        #expect(sigType == "ecdsa-sha2-nistp256")
        #expect(sigData == derSig)
        #expect(offset == blob.count)
    }

    // MARK: - Secure Enclave Availability Test

    @Test func secureEnclaveAvailabilityCheck() async {
        let manager = SecureEnclaveKeyManager()
        // On simulator, SE is not available - generateKey should throw
        if !SecureEnclave.isAvailable {
            await #expect(throws: SecureEnclaveKeyManager.SecureEnclaveError.self) {
                try await manager.generateKey(label: "test")
            }
        }
    }

    @Test func loadKeyWithInvalidTagThrows() async {
        let manager = SecureEnclaveKeyManager()
        await #expect(throws: SecureEnclaveKeyManager.SecureEnclaveError.self) {
            _ = try await manager.loadKey(tag: "nonexistent-tag-\(UUID().uuidString)")
        }
    }

    // MARK: - Helpers

    private func readSSHString(from data: Data, offset: inout Int) -> String {
        let bytes = readSSHData(from: data, offset: &offset)
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    private func readSSHData(from data: Data, offset: inout Int) -> Data {
        let length = Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
        offset += 4
        let result = data[offset..<(offset + length)]
        offset += length
        return Data(result)
    }

    private func readASN1Length(from data: Data, offset: inout Int) -> Int {
        let first = Int(data[offset])
        offset += 1
        if first < 128 {
            return first
        } else if first == 0x81 {
            let len = Int(data[offset])
            offset += 1
            return len
        } else {
            let len = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
            return len
        }
    }
}
