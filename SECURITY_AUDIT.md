# Security Audit Report — DivineMarssh

**Date:** 2026-03-14
**Scope:** Full application source, focus on secrets storage
**Severity scale:** CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## Executive Summary

The app demonstrates strong security fundamentals: Keychain-based credential storage, Secure Enclave key generation, strict SSH algorithm policy, Swift 6 concurrency safety, and memory hygiene utilities. Several medium-severity gaps were identified, primarily around inconsistent biometric protection and missing iCloud backup exclusions for metadata files.

---

## 1. Secrets Storage

### Passwords — MEDIUM risk

Passwords are stored in iOS Keychain with service `com.divinemarssh.passwords` and accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. This is a solid baseline.

**Finding [M1] — No biometric gate on password retrieval.**
Imported SSH keys require biometric authentication (`.biometryCurrentSet` access control flag), but passwords do not. Any code running while the device is unlocked can read stored passwords via `SecItemCopyMatching` without user interaction.

*Recommendation:* Add `SecAccessControlCreateWithFlags` with `.biometryCurrentSet` to password Keychain items, matching the imported-key protection level.

### Imported SSH Keys — Strong

- Stored in Keychain with service `com.divinemarssh.imported-keys`
- Protected by `.biometryCurrentSet` access control when biometric is enabled
- Supports encrypted OpenSSH key formats (bcrypt-pbkdf KDF, AES-256-CTR/CBC)
- Private key material never written to disk outside Keychain

### Secure Enclave Keys — Strong

- Hardware-backed P-256 ECDSA via `SecureEnclave.P256.Signing.PrivateKey`
- Biometric protection enabled (`.biometryCurrentSet`)
- Only public key metadata persisted to JSON; private keys never leave SE

### Memory Hygiene — Good

- `MemoryHygiene` utility zeroes sensitive buffers via function-pointer `memset` to prevent compiler dead-store elimination
- Sensitive logging disabled globally (`sensitiveLoggingDisabled = true`)

---

## 2. Data Persistence & Backup

### Finding [M2] — Profile metadata not excluded from iCloud backup

`profiles.json` (hostnames, usernames, port numbers, auth method references, last-connected timestamps) is stored in `applicationSupportDirectory` **without** `isExcludedFromBackup = true`.

`known_hosts.json` is correctly excluded. `profiles.json`, `imported-keys.json`, and `se-keys.json` are not.

While private keys are safe in Keychain/SE (which has its own backup policy), the metadata leaks connection targets and usernames to iCloud backups. An attacker with iCloud access learns the user's server inventory.

*Recommendation:* Set `isExcludedFromBackup = true` on all files in the app's storage directory, or at minimum on `profiles.json`, `imported-keys.json`, and `se-keys.json`.

### Finding [INFO] — Terminal state cache

`TerminalStateCache` persists terminal output. If a session displays sensitive content (tokens, env vars), it may be written to disk. Not excluded from backup.

*Recommendation:* Evaluate whether terminal state cache should be excluded from backup or auto-purged.

---

## 3. SSH Protocol & Crypto

### Algorithm Policy — Strong

The `AlgorithmPolicy` enforces modern-only algorithms:

| Category | Allowed | Rejected |
|---|---|---|
| Ciphers | AES-256-GCM, AES-128-GCM | 3DES, ARC4, CBC modes |
| KEX | ECDH (P-256/384/521), Curve25519 | DH group1/group14 |
| Host keys | Ed25519, ECDSA (P-256/384/521) | RSA-SHA1, DSS |

This effectively mitigates Terrapin (CVE-2023-48795) by excluding CBC and ChaCha20-Poly1305.

### Host Key Verification — Strong

- Proper TOFU model with SHA-256 fingerprints
- Mismatch detection with user-facing warning UI
- New hosts require explicit user approval
- Known hosts stored atomically with backup exclusion

---

## 4. Input Validation

### Finding [L1] — Weak connection parameter validation

`ConnectionViewModel.validateFields()` checks only:
- Host is not empty
- Username is not empty
- Port is not zero

Missing:
- No hostname format validation (RFC 952/1123, IPv4, IPv6)
- No port range enforcement (1–65535); `UInt16` type limits to 0–65535 but 0 is only rejected explicitly
- No length limits on hostname or username
- Invalid port strings silently default to 22 via `UInt16(portString) ?? 22`

*Recommendation:* Add hostname regex validation, explicit port range check (1–65535), and reasonable length limits.

---

## 5. Concurrency Safety — Strong

The project enforces `SWIFT_STRICT_CONCURRENCY: complete` (Swift 6). All credential stores are `actor` types:

- `ProfileStore`, `KnownHostsStore`, `KeyManager`, `SSHSession`, `HostKeyVerifier`, `SecureEnclaveKeyManager`, `KeychainKeyManager`

All model types are `Sendable`. No data races detected in credential access patterns.

---

## 6. Third-Party Dependencies

| Package | Version | Role | Notes |
|---|---|---|---|
| Citadel | 0.9.0+ | SSH client | Actively maintained |
| SwiftNIO SSH | 0.3.4+ | SSH protocol | Apple-maintained |
| SwiftTerm | 1.2.0+ | Terminal emulation | Mature |
| SwiftNIO | 2.65.0+ | Async networking | Apple-maintained |

No known CVEs at time of audit. Recommend periodic dependency review.

---

## 7. Entitlements & Permissions

- `ITSAppUsesNonExemptEncryption: false` — correct (system crypto frameworks)
- `NSCameraUsageDescription` — for QR code scanning of SSH keys (appropriate)
- `NSFaceIDUsageDescription` — for biometric authentication (appropriate)

### Finding [L2] — No explicit entitlements file

The project relies on default entitlements. An explicit `.entitlements` file would provide defense-in-depth and make the permission surface auditable.

---

## 8. Git & Build Hygiene

- `.gitignore` excludes Xcode user data, build artifacts, and dependency caches
- Recent commit `db36d4e` removed test SSH private keys from repo — good response, but **the keys remain in git history**

### Finding [M3] — Test SSH keys in git history

Commit history contains SSH private keys that were later removed. If these keys were ever used in production, they should be considered compromised.

*Recommendation:* Confirm test keys were never used outside test environments. Consider `git filter-repo` to purge from history if the repo is not yet widely distributed.

---

## Findings Summary

| ID | Severity | Finding | Status |
|---|---|---|---|
| M1 | MEDIUM | Passwords lack biometric protection on retrieval | Open |
| M2 | MEDIUM | Profile/key metadata not excluded from iCloud backup | Open |
| M3 | MEDIUM | Test SSH private keys remain in git history | Open |
| L1 | LOW | Connection parameter validation is minimal | Open |
| L2 | LOW | No explicit entitlements file | Open |
| I1 | INFO | Terminal state cache may persist sensitive output | Open |

---

## Strengths

- Keychain storage with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Secure Enclave integration with biometric protection
- Modern-only SSH algorithm policy (AES-GCM, ECDH, Ed25519)
- Proper TOFU host key verification with user-facing UI
- Memory hygiene utilities to zero sensitive buffers
- Swift 6 strict concurrency (actor-based stores, Sendable models)
- Sensitive logging disabled globally
