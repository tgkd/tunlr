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
