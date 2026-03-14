import Testing
import Foundation
@testable import DivineMarssh

@Suite("FingerprintURIParser")
struct FingerprintURIParserTests {

    // MARK: - Valid URIs

    @Test func parsesValidURIWithExplicitPort() throws {
        let uri = "ssh-trust://example.com:2222?fp=SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.hostname == "example.com")
        #expect(result.port == 2222)
        #expect(result.fingerprint == "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
        #expect(result.keyType == "ssh-ed25519")
    }

    @Test func parsesValidURIWithDefaultPort() throws {
        let uri = "ssh-trust://myserver.local?fp=SHA256:abc123DEFghi&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.hostname == "myserver.local")
        #expect(result.port == 22)
    }

    @Test func parsesValidURIWithRSAKeyType() throws {
        let uri = "ssh-trust://host.example:22?fp=SHA256:AAAA&type=ssh-rsa"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.keyType == "ssh-rsa")
    }

    @Test func parsesValidURIWithECDSA256() throws {
        let uri = "ssh-trust://host:443?fp=SHA256:fingerprint&type=ecdsa-sha2-nistp256"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.keyType == "ecdsa-sha2-nistp256")
        #expect(result.port == 443)
    }

    @Test func parsesValidURIWithECDSA384() throws {
        let uri = "ssh-trust://host:22?fp=SHA256:xyz&type=ecdsa-sha2-nistp384"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.keyType == "ecdsa-sha2-nistp384")
    }

    @Test func parsesValidURIWithECDSA521() throws {
        let uri = "ssh-trust://host:22?fp=SHA256:xyz&type=ecdsa-sha2-nistp521"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.keyType == "ecdsa-sha2-nistp521")
    }

    @Test func parsesIPv4Host() throws {
        let uri = "ssh-trust://192.168.1.100:22?fp=SHA256:abc&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.hostname == "192.168.1.100")
    }

    @Test func parsesPort1() throws {
        let uri = "ssh-trust://host:1?fp=SHA256:abc&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.port == 1)
    }

    @Test func parsesPort65535() throws {
        let uri = "ssh-trust://host:65535?fp=SHA256:abc&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.port == 65535)
    }

    @Test func parsesFingerprintWithSlashAndPlus() throws {
        let uri = "ssh-trust://host:22?fp=SHA256:abc+def/ghi&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.fingerprint == "SHA256:abc+def/ghi")
    }

    @Test func parsesFingerprintWithPaddingEquals() throws {
        let uri = "ssh-trust://host:22?fp=SHA256:abc123==&type=ssh-ed25519"
        let result = try FingerprintURIParser.parse(uri)
        #expect(result.fingerprint == "SHA256:abc123==")
    }

    // MARK: - Invalid Scheme

    @Test func rejectsHTTPScheme() {
        let uri = "http://example.com?fp=SHA256:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidScheme) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsEmptyScheme() {
        let uri = "://host?fp=SHA256:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidScheme) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsNoScheme() {
        let uri = "example.com?fp=SHA256:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidScheme) {
            try FingerprintURIParser.parse(uri)
        }
    }

    // MARK: - Missing Host

    @Test func rejectsMissingHost() {
        let uri = "ssh-trust://?fp=SHA256:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.missingHost) {
            try FingerprintURIParser.parse(uri)
        }
    }

    // MARK: - Invalid Port

    @Test func rejectsPort0() {
        let uri = "ssh-trust://host:0?fp=SHA256:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidPort) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsNegativePort() {
        let uri = "ssh-trust://host:-1?fp=SHA256:abc&type=ssh-ed25519"
        // URLComponents may not parse negative ports; depends on implementation
        do {
            _ = try FingerprintURIParser.parse(uri)
            Issue.record("Expected error for negative port")
        } catch {
            // Any error is acceptable for malformed port
        }
    }

    // MARK: - Missing/Invalid Fingerprint

    @Test func rejectsMissingFingerprintParam() {
        let uri = "ssh-trust://host:22?type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.missingFingerprint) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsEmptyFingerprint() {
        let uri = "ssh-trust://host:22?fp=&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.missingFingerprint) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsFingerprintWithoutSHA256Prefix() {
        let uri = "ssh-trust://host:22?fp=MD5:abc&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidFingerprintFormat) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsFingerprintWithOnlySHA256Prefix() {
        let uri = "ssh-trust://host:22?fp=SHA256:&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidFingerprintFormat) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsFingerprintWithInvalidCharacters() {
        let uri = "ssh-trust://host:22?fp=SHA256:abc!@%23&type=ssh-ed25519"
        #expect(throws: FingerprintURIParserError.invalidFingerprintFormat) {
            try FingerprintURIParser.parse(uri)
        }
    }

    // MARK: - Missing/Invalid Key Type

    @Test func rejectsMissingKeyType() {
        let uri = "ssh-trust://host:22?fp=SHA256:abc"
        #expect(throws: FingerprintURIParserError.missingKeyType) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsEmptyKeyType() {
        let uri = "ssh-trust://host:22?fp=SHA256:abc&type="
        #expect(throws: FingerprintURIParserError.missingKeyType) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsUnsupportedKeyType() {
        let uri = "ssh-trust://host:22?fp=SHA256:abc&type=ssh-dss"
        #expect(throws: FingerprintURIParserError.unsupportedKeyType("ssh-dss")) {
            try FingerprintURIParser.parse(uri)
        }
    }

    @Test func rejectsArbitraryKeyType() {
        let uri = "ssh-trust://host:22?fp=SHA256:abc&type=not-a-key-type"
        #expect(throws: FingerprintURIParserError.unsupportedKeyType("not-a-key-type")) {
            try FingerprintURIParser.parse(uri)
        }
    }

    // MARK: - No Query Parameters

    @Test func rejectsURIWithNoQueryParams() {
        let uri = "ssh-trust://host:22"
        #expect(throws: FingerprintURIParserError.missingFingerprint) {
            try FingerprintURIParser.parse(uri)
        }
    }

    // MARK: - URI Builder

    @Test func buildURIWithNonDefaultPort() {
        let uri = FingerprintURIParser.buildURI(
            hostname: "example.com",
            port: 2222,
            fingerprint: "SHA256:testfp",
            keyType: "ssh-ed25519"
        )
        #expect(uri.contains("ssh-trust://"))
        #expect(uri.contains("example.com"))
        #expect(uri.contains("2222"))
        #expect(uri.contains("fp=SHA256:testfp"))
        #expect(uri.contains("type=ssh-ed25519"))
    }

    @Test func buildURIOmitsDefaultPort() {
        let uri = FingerprintURIParser.buildURI(
            hostname: "example.com",
            port: 22,
            fingerprint: "SHA256:abc",
            keyType: "ssh-ed25519"
        )
        #expect(!uri.contains(":22"))
    }

    @Test func buildURIRoundTrips() throws {
        let uri = FingerprintURIParser.buildURI(
            hostname: "server.example.com",
            port: 8022,
            fingerprint: "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU",
            keyType: "ssh-ed25519"
        )
        let parsed = try FingerprintURIParser.parse(uri)
        #expect(parsed.hostname == "server.example.com")
        #expect(parsed.port == 8022)
        #expect(parsed.fingerprint == "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
        #expect(parsed.keyType == "ssh-ed25519")
    }

    // MARK: - Parsed Fingerprint Model

    @Test func parsedFingerprintEquality() {
        let a = ParsedFingerprint(hostname: "h", port: 22, fingerprint: "SHA256:x", keyType: "ssh-ed25519")
        let b = ParsedFingerprint(hostname: "h", port: 22, fingerprint: "SHA256:x", keyType: "ssh-ed25519")
        #expect(a == b)
    }

    @Test func parsedFingerprintInequality() {
        let a = ParsedFingerprint(hostname: "h1", port: 22, fingerprint: "SHA256:x", keyType: "ssh-ed25519")
        let b = ParsedFingerprint(hostname: "h2", port: 22, fingerprint: "SHA256:x", keyType: "ssh-ed25519")
        #expect(a != b)
    }

    // MARK: - Supported Key Types

    @Test func schemeIsSSHTrust() {
        #expect(FingerprintURIParser.scheme == "ssh-trust")
    }

    @Test func supportedKeyTypesContainsExpected() {
        #expect(FingerprintURIParser.supportedKeyTypes.contains("ssh-ed25519"))
        #expect(FingerprintURIParser.supportedKeyTypes.contains("ssh-rsa"))
        #expect(FingerprintURIParser.supportedKeyTypes.contains("ecdsa-sha2-nistp256"))
        #expect(FingerprintURIParser.supportedKeyTypes.contains("ecdsa-sha2-nistp384"))
        #expect(FingerprintURIParser.supportedKeyTypes.contains("ecdsa-sha2-nistp521"))
    }
}
