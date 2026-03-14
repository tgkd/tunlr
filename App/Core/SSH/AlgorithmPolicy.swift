import Foundation
@preconcurrency import Citadel

enum AlgorithmPolicy {

    enum PolicyError: Error, Equatable {
        case legacyCipherRejected(String)
        case legacyKEXRejected(String)
        case legacyHostKeyRejected(String)
    }

    static let allowedCipherNames: Set<String> = [
        "aes256-gcm@openssh.com",
        "aes128-gcm@openssh.com",
    ]

    static let rejectedCipherNames: Set<String> = [
        "aes128-ctr",
        "aes192-ctr",
        "aes256-ctr",
        "aes128-cbc",
        "aes256-cbc",
        "3des-cbc",
        "arcfour",
    ]

    static let allowedKEXNames: Set<String> = [
        "ecdh-sha2-nistp256",
        "ecdh-sha2-nistp384",
        "ecdh-sha2-nistp521",
        "curve25519-sha256",
        "curve25519-sha256@libssh.org",
    ]

    static let rejectedKEXNames: Set<String> = [
        "diffie-hellman-group14-sha1",
        "diffie-hellman-group1-sha1",
        "diffie-hellman-group-exchange-sha1",
    ]

    static let allowedHostKeyTypes: Set<String> = [
        "ssh-ed25519",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
    ]

    static let rejectedHostKeyTypes: Set<String> = [
        "ssh-rsa",
        "ssh-dss",
    ]

    /// Returns an `SSHAlgorithms` configuration that uses only modern algorithms.
    ///
    /// The default `SSHAlgorithms()` (no modifications) uses NIOSSH's built-in
    /// defaults which are already modern: ECDH key exchange (P-256, P-384,
    /// P-521, Curve25519) and AES-GCM transport protection. This avoids
    /// Citadel's `.all` preset which adds legacy algorithms like
    /// DiffieHellmanGroup14-SHA1 and AES128-CTR.
    static func makeSecureAlgorithms() -> SSHAlgorithms {
        SSHAlgorithms()
    }

    static func validateCipher(_ name: String) throws {
        if rejectedCipherNames.contains(name) {
            throw PolicyError.legacyCipherRejected(name)
        }
    }

    static func validateKEX(_ name: String) throws {
        if rejectedKEXNames.contains(name) {
            throw PolicyError.legacyKEXRejected(name)
        }
    }

    static func validateHostKeyType(_ name: String) throws {
        if rejectedHostKeyTypes.contains(name) {
            throw PolicyError.legacyHostKeyRejected(name)
        }
    }

    static func isCipherAllowed(_ name: String) -> Bool {
        allowedCipherNames.contains(name)
    }

    static func isKEXAllowed(_ name: String) -> Bool {
        allowedKEXNames.contains(name)
    }

    static func isHostKeyTypeAllowed(_ name: String) -> Bool {
        allowedHostKeyTypes.contains(name)
    }

    /// SwiftNIO SSH uses AES-GCM ciphers by default, which are not affected by
    /// Terrapin (CVE-2023-48795). Terrapin targets ChaCha20-Poly1305 and
    /// CBC-EtM ciphers with sequence number manipulation during the handshake.
    /// Since this app's default `SSHAlgorithms()` uses AES-GCM-only transport
    /// protection (no CTR or CBC modes), the Terrapin attack surface is absent.
    static let terrapinMitigationNote = """
        CVE-2023-48795 (Terrapin) targets ChaCha20-Poly1305 and CBC-EtM \
        cipher suites via sequence number manipulation during key exchange. \
        This app's algorithm policy restricts transport protection to \
        AES-GCM-only modes, which are not vulnerable to this attack.
        """
}
