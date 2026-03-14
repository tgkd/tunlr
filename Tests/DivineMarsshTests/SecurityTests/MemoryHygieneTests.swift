import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Zero Out Tests

struct MemoryHygieneZeroOutTests {

    @Test func zeroOutClearsBytes() {
        var bytes: [UInt8] = [0x41, 0x42, 0x43, 0x44, 0x45]
        MemoryHygiene.zeroOut(&bytes)
        #expect(bytes.isEmpty)
    }

    @Test func zeroOutEmptyArrayIsNoOp() {
        var bytes: [UInt8] = []
        MemoryHygiene.zeroOut(&bytes)
        #expect(bytes.isEmpty)
    }

    @Test func zeroOutClearsData() {
        var data = Data([0x01, 0x02, 0x03, 0x04])
        MemoryHygiene.zeroOut(&data)
        #expect(data.isEmpty)
    }

    @Test func zeroOutEmptyDataIsNoOp() {
        var data = Data()
        MemoryHygiene.zeroOut(&data)
        #expect(data.isEmpty)
    }

    @Test func zeroOutLargeArray() {
        var bytes = [UInt8](repeating: 0xFF, count: 4096)
        #expect(bytes.count == 4096)
        MemoryHygiene.zeroOut(&bytes)
        #expect(bytes.isEmpty)
    }

    @Test func zeroOutSingleByte() {
        var bytes: [UInt8] = [0xAB]
        MemoryHygiene.zeroOut(&bytes)
        #expect(bytes.isEmpty)
    }
}

// MARK: - Secure Bytes Tests

struct MemoryHygieneSecureBytesTests {

    @Test func withSecureBytesProvidesCopy() {
        let original: [UInt8] = [0x01, 0x02, 0x03]
        let result = MemoryHygiene.withSecureBytes(original) { bytes -> Int in
            bytes.count
        }
        #expect(result == 3)
        #expect(original == [0x01, 0x02, 0x03])
    }

    @Test func withSecureBytesAllowsTransformation() {
        let passphrase: [UInt8] = Array("secret".utf8)
        let hash = MemoryHygiene.withSecureBytes(passphrase) { bytes -> Int in
            bytes.reduce(0) { $0 &+ Int($1) }
        }
        #expect(hash > 0)
    }

    @Test func passphraseToBytes() {
        let bytes = MemoryHygiene.passphraseToBytes("hello")
        #expect(bytes == [0x68, 0x65, 0x6C, 0x6C, 0x6F])
    }

    @Test func passphraseToBytesEmpty() {
        let bytes = MemoryHygiene.passphraseToBytes("")
        #expect(bytes.isEmpty)
    }

    @Test func passphraseToBytesUnicode() {
        let bytes = MemoryHygiene.passphraseToBytes("\u{1F512}")
        #expect(!bytes.isEmpty)
        #expect(bytes.count == 4)
    }
}

// MARK: - Sanitization Tests

struct MemoryHygieneSanitizeTests {

    @Test func sanitizeStringRedacts() {
        let result = MemoryHygiene.sanitize("my-secret-password")
        #expect(result == "[REDACTED]")
        #expect(!result.contains("secret"))
    }

    @Test func sanitizeDataRedacts() {
        let data = Data([0x01, 0x02, 0x03])
        let result = MemoryHygiene.sanitize(data)
        #expect(result == "[REDACTED 3 bytes]")
    }

    @Test func sanitizeCustomLabel() {
        let result = MemoryHygiene.sanitize("password123", label: "PASSWORD")
        #expect(result == "[PASSWORD]")
    }

    @Test func sanitizeDataCustomLabel() {
        let data = Data(repeating: 0xAB, count: 32)
        let result = MemoryHygiene.sanitize(data, label: "KEY_MATERIAL")
        #expect(result == "[KEY_MATERIAL 32 bytes]")
    }

    @Test func sensitiveLoggingIsDisabled() {
        #expect(MemoryHygiene.sensitiveLoggingDisabled)
    }

    @Test func sanitizeEmptyStringStillRedacts() {
        let result = MemoryHygiene.sanitize("")
        #expect(result == "[REDACTED]")
    }

    @Test func sanitizeEmptyDataShowsZeroBytes() {
        let result = MemoryHygiene.sanitize(Data())
        #expect(result == "[REDACTED 0 bytes]")
    }
}

// MARK: - Memory Zeroing Verification

struct MemoryHygieneVerificationTests {

    @Test func zeroedBytesDoNotRetainOriginalContent() {
        var bytes: [UInt8] = Array("SuperSecretPassphrase123!".utf8)
        let originalCount = bytes.count
        #expect(originalCount > 0)

        MemoryHygiene.zeroOut(&bytes)

        #expect(bytes.isEmpty)
        #expect(bytes.count == 0)
    }

    @Test func zeroedDataDoesNotRetainOriginalContent() {
        var data = Data("PrivateKeyMaterial".utf8)
        let originalCount = data.count
        #expect(originalCount > 0)

        MemoryHygiene.zeroOut(&data)

        #expect(data.isEmpty)
        #expect(data.count == 0)
    }

    @Test func multipleZeroOutCallsAreSafe() {
        var bytes: [UInt8] = [0x01, 0x02, 0x03]
        MemoryHygiene.zeroOut(&bytes)
        MemoryHygiene.zeroOut(&bytes)
        MemoryHygiene.zeroOut(&bytes)
        #expect(bytes.isEmpty)
    }
}
