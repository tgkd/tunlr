import Foundation
@preconcurrency import Citadel

enum AlgorithmPolicy {

    /// Returns an `SSHAlgorithms` configuration that uses only modern algorithms.
    ///
    /// The default `SSHAlgorithms()` (no modifications) uses NIOSSH's built-in
    /// defaults which are already modern: ECDH key exchange (P-256, P-384,
    /// P-521, Curve25519) and AES-GCM transport protection. This avoids
    /// Citadel's `.all` preset which adds legacy algorithms like
    /// DiffieHellmanGroup14-SHA1 and AES128-CTR. AES-GCM-only transport also
    /// keeps the app clear of Terrapin (CVE-2023-48795), which targets
    /// ChaCha20-Poly1305 and CBC-EtM cipher suites.
    static func makeSecureAlgorithms() -> SSHAlgorithms {
        SSHAlgorithms()
    }
}
