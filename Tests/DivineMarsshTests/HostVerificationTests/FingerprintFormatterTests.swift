import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

struct FingerprintFormatterTests {

    // MARK: - SHA256 Fingerprint Format

    @Test func sha256FingerprintHasCorrectPrefix() {
        let data = Data(repeating: 0x42, count: 32)
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: data)
        #expect(fingerprint.hasPrefix("SHA256:"))
    }

    @Test func sha256FingerprintNoPaddingEquals() {
        let data = Data(repeating: 0x42, count: 32)
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: data)
        #expect(!fingerprint.contains("="))
    }

    @Test func sha256FingerprintUsesBase64Characters() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: data)
        let base64Part = String(fingerprint.dropFirst("SHA256:".count))
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/"))
        let charSet = CharacterSet(charactersIn: base64Part)
        #expect(charSet.isSubset(of: validChars))
    }

    @Test func sha256FingerprintDeterministic() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let fp1 = FingerprintFormatter.sha256Fingerprint(of: data)
        let fp2 = FingerprintFormatter.sha256Fingerprint(of: data)
        #expect(fp1 == fp2)
    }

    @Test func sha256FingerprintDiffersForDifferentKeys() {
        let data1 = Data([0x01, 0x02, 0x03])
        let data2 = Data([0x04, 0x05, 0x06])
        let fp1 = FingerprintFormatter.sha256Fingerprint(of: data1)
        let fp2 = FingerprintFormatter.sha256Fingerprint(of: data2)
        #expect(fp1 != fp2)
    }

    @Test func sha256FingerprintMatchesManualComputation() {
        let data = Data([0x00, 0x00, 0x00, 0x0b]) + "ssh-ed25519".data(using: .utf8)!
            + Data([0x00, 0x00, 0x00, 0x20]) + Data(repeating: 0xAA, count: 32)

        let hash = SHA256.hash(data: data)
        let expectedBase64 = Data(hash).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let expected = "SHA256:\(expectedBase64)"

        let result = FingerprintFormatter.sha256Fingerprint(of: data)
        #expect(result == expected)
    }

    // MARK: - Hex Fingerprint Format

    @Test func hexFingerprintUsesColonSeparatedHex() {
        let data = Data([0xCA, 0xFE])
        let fingerprint = FingerprintFormatter.hexFingerprint(of: data)
        let components = fingerprint.split(separator: ":")
        #expect(components.count == 32) // SHA256 = 32 bytes
        for component in components {
            #expect(component.count == 2)
        }
    }

    @Test func hexFingerprintDeterministic() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let fp1 = FingerprintFormatter.hexFingerprint(of: data)
        let fp2 = FingerprintFormatter.hexFingerprint(of: data)
        #expect(fp1 == fp2)
    }

    @Test func hexFingerprintMatchesManualComputation() {
        let data = Data([0x01, 0x02, 0x03])
        let hash = SHA256.hash(data: data)
        let expected = hash.map { String(format: "%02x", $0) }.joined(separator: ":")
        let result = FingerprintFormatter.hexFingerprint(of: data)
        #expect(result == expected)
    }

    // MARK: - Known Test Vector

    @Test func sha256FingerprintMatchesKnownVector() {
        // SHA256 of empty data is e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let data = Data()
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: data)
        // SHA256("") in base64 without padding = 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU
        #expect(fingerprint == "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
    }
}
