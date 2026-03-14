import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Cipher Policy Tests

struct AlgorithmPolicyCipherTests {

    @Test func aes256GCMIsAllowed() {
        #expect(AlgorithmPolicy.isCipherAllowed("aes256-gcm@openssh.com"))
    }

    @Test func aes128GCMIsAllowed() {
        #expect(AlgorithmPolicy.isCipherAllowed("aes128-gcm@openssh.com"))
    }

    @Test func aes128CTRIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("aes128-ctr")
        }
    }

    @Test func aes256CTRIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("aes256-ctr")
        }
    }

    @Test func aes128CBCIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("aes128-cbc")
        }
    }

    @Test func aes256CBCIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("aes256-cbc")
        }
    }

    @Test func tripleDesCBCIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("3des-cbc")
        }
    }

    @Test func arcfourIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateCipher("arcfour")
        }
    }

    @Test func unknownCipherPassesValidation() throws {
        try AlgorithmPolicy.validateCipher("future-cipher-v2")
    }

    @Test func aes128CTRIsNotInAllowedSet() {
        #expect(!AlgorithmPolicy.isCipherAllowed("aes128-ctr"))
    }

    @Test func rejectedCipherErrorContainsName() throws {
        do {
            try AlgorithmPolicy.validateCipher("3des-cbc")
            Issue.record("Expected error")
        } catch let error as AlgorithmPolicy.PolicyError {
            #expect(error == .legacyCipherRejected("3des-cbc"))
        }
    }
}

// MARK: - KEX Policy Tests

struct AlgorithmPolicyKEXTests {

    @Test func curve25519IsAllowed() {
        #expect(AlgorithmPolicy.isKEXAllowed("curve25519-sha256"))
    }

    @Test func curve25519LibsshIsAllowed() {
        #expect(AlgorithmPolicy.isKEXAllowed("curve25519-sha256@libssh.org"))
    }

    @Test func ecdhP256IsAllowed() {
        #expect(AlgorithmPolicy.isKEXAllowed("ecdh-sha2-nistp256"))
    }

    @Test func ecdhP384IsAllowed() {
        #expect(AlgorithmPolicy.isKEXAllowed("ecdh-sha2-nistp384"))
    }

    @Test func ecdhP521IsAllowed() {
        #expect(AlgorithmPolicy.isKEXAllowed("ecdh-sha2-nistp521"))
    }

    @Test func dhGroup14Sha1IsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateKEX("diffie-hellman-group14-sha1")
        }
    }

    @Test func dhGroup1Sha1IsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateKEX("diffie-hellman-group1-sha1")
        }
    }

    @Test func dhGroupExchangeSha1IsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateKEX("diffie-hellman-group-exchange-sha1")
        }
    }

    @Test func dhGroup14Sha1IsNotInAllowedSet() {
        #expect(!AlgorithmPolicy.isKEXAllowed("diffie-hellman-group14-sha1"))
    }

    @Test func rejectedKEXErrorContainsName() throws {
        do {
            try AlgorithmPolicy.validateKEX("diffie-hellman-group1-sha1")
            Issue.record("Expected error")
        } catch let error as AlgorithmPolicy.PolicyError {
            #expect(error == .legacyKEXRejected("diffie-hellman-group1-sha1"))
        }
    }
}

// MARK: - Host Key Type Policy Tests

struct AlgorithmPolicyHostKeyTests {

    @Test func ed25519IsAllowed() {
        #expect(AlgorithmPolicy.isHostKeyTypeAllowed("ssh-ed25519"))
    }

    @Test func ecdsaP256IsAllowed() {
        #expect(AlgorithmPolicy.isHostKeyTypeAllowed("ecdsa-sha2-nistp256"))
    }

    @Test func ecdsaP384IsAllowed() {
        #expect(AlgorithmPolicy.isHostKeyTypeAllowed("ecdsa-sha2-nistp384"))
    }

    @Test func ecdsaP521IsAllowed() {
        #expect(AlgorithmPolicy.isHostKeyTypeAllowed("ecdsa-sha2-nistp521"))
    }

    @Test func rsaIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateHostKeyType("ssh-rsa")
        }
    }

    @Test func dssIsRejected() throws {
        #expect(throws: AlgorithmPolicy.PolicyError.self) {
            try AlgorithmPolicy.validateHostKeyType("ssh-dss")
        }
    }

    @Test func rsaIsNotInAllowedSet() {
        #expect(!AlgorithmPolicy.isHostKeyTypeAllowed("ssh-rsa"))
    }

    @Test func rejectedHostKeyErrorContainsName() throws {
        do {
            try AlgorithmPolicy.validateHostKeyType("ssh-dss")
            Issue.record("Expected error")
        } catch let error as AlgorithmPolicy.PolicyError {
            #expect(error == .legacyHostKeyRejected("ssh-dss"))
        }
    }
}

// MARK: - Algorithm Configuration Tests

struct AlgorithmPolicyConfigTests {

    @Test func secureAlgorithmsUsesNIOSSHDefaults() {
        let algorithms = AlgorithmPolicy.makeSecureAlgorithms()
        // nil means "use NIOSSH built-in defaults" which are already modern
        // (ECDH key exchange + AES-GCM transport protection).
        // NOT using Citadel's .all avoids adding legacy DH/AES-CTR.
        #expect(algorithms.transportProtectionSchemes == nil)
        #expect(algorithms.keyExchangeAlgorithms == nil)
    }

    @Test func terrapinMitigationNoteIsPresent() {
        let note = AlgorithmPolicy.terrapinMitigationNote
        #expect(note.contains("CVE-2023-48795"))
        #expect(note.contains("AES-GCM"))
    }

    @Test func policyErrorEquatable() {
        let a = AlgorithmPolicy.PolicyError.legacyCipherRejected("aes128-cbc")
        let b = AlgorithmPolicy.PolicyError.legacyCipherRejected("aes128-cbc")
        let c = AlgorithmPolicy.PolicyError.legacyCipherRejected("3des-cbc")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func allAllowedCiphersAreModern() {
        for cipher in AlgorithmPolicy.allowedCipherNames {
            #expect(cipher.contains("gcm"))
        }
    }

    @Test func noOverlapBetweenAllowedAndRejectedCiphers() {
        let overlap = AlgorithmPolicy.allowedCipherNames.intersection(AlgorithmPolicy.rejectedCipherNames)
        #expect(overlap.isEmpty)
    }

    @Test func noOverlapBetweenAllowedAndRejectedKEX() {
        let overlap = AlgorithmPolicy.allowedKEXNames.intersection(AlgorithmPolicy.rejectedKEXNames)
        #expect(overlap.isEmpty)
    }

    @Test func noOverlapBetweenAllowedAndRejectedHostKeys() {
        let overlap = AlgorithmPolicy.allowedHostKeyTypes.intersection(AlgorithmPolicy.rejectedHostKeyTypes)
        #expect(overlap.isEmpty)
    }
}
