# Building a secure iOS SSH terminal from scratch

**The optimal architecture for a native iOS SSH terminal combines Apple's SwiftNIO SSH (or the higher-level Citadel library) with SwiftTerm for terminal emulation, Secure Enclave P-256 keys for maximum-security authentication, and iOS Keychain with biometric gating for imported Ed25519/RSA keys.** This stack is pure Swift, uses only permissive licenses, avoids C dependencies entirely, and aligns with how shipping apps like Prompt 3, Blink Shell, and ShellFish already solve these problems. The primary iOS-specific constraint to design around is that **background SSH sessions cannot be kept alive** — the platform will suspend your app within ~30 seconds of backgrounding.

This report covers every layer of the stack: SSH library selection, cryptographic key management, transport hardening, sandbox constraints, terminal rendering, and lessons from production apps.

---

## SSH library landscape narrows to two real options

The iOS SSH library ecosystem has consolidated. After evaluating seven candidates, only two paths make sense for a new project in 2026.

**Citadel + SwiftNIO SSH (recommended for new projects).** Apple maintains [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) (Apache 2.0, ~466 stars), a pure-Swift SSH-2 implementation built on SwiftNIO. It supports **Ed25519, ECDSA P-256/P-384/P-521, AES-GCM, and Curve25519 key exchange** — modern algorithms only, no legacy cruft. [Citadel](https://github.com/orlandos-nl/Citadel) (MIT, ~305 stars) wraps SwiftNIO SSH with a high-level async/await API and adds **SFTP, SSH jump hosts, OpenSSH key parsing, and command execution**. Together they form a complete SSH client with zero C dependencies, full iOS compatibility via SPM, and Swift 6 concurrency safety. Citadel also backfills some algorithms SwiftNIO SSH lacks — `diffie-hellman-group14-sha256` and RSA key support (marked `Insecure.RSA.PrivateKey`, pending upstream changes). The integration pattern is clean:

```swift
let client = try await SSHClient.connect(
    host: "server.local", port: 22,
    authenticationMethod: .ed25519(privateKey),
    hostKeyValidator: .custom { hostKey in /* your TOFU logic */ }
)
let output = try await client.executeCommand("uptime")
```

Use [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) to run SwiftNIO atop `Network.framework` on iOS, gaining automatic Wi-Fi/cellular failover and Happy Eyeballs IPv4/IPv6 racing for free.

**libssh2 (fallback for legacy servers).** If your homelab includes older devices running OpenSSH < 7.4 or embedded systems with only CBC ciphers and SHA-1 KEX, SwiftNIO SSH will refuse to connect. libssh2 (BSD license, v1.11.1) supports every cipher from `chacha20-poly1305` down to `3des-cbc`. Cross-compile it for iOS using [libssh2-iosx](https://github.com/apotocki/libssh2-iosx) (CocoaPods/xcframework) or [Libssh2Prebuild](https://github.com/DimaRU/Libssh2Prebuild) (SPM binary target). The cost is bundling OpenSSL (~3–5 MB), managing cross-compilation for arm64 device and simulator slices, and wrapping a C API. Miguel de Icaza's [SwiftSH fork](https://github.com/migueldeicaza/SwiftSH) provides a Swift wrapper with callback-based auth including Secure Enclave support.

**Libraries to avoid.** NMSSH (~765 stars, MIT) wraps libssh2 in Objective-C but is effectively unmaintained — its bundled OpenSSL binaries are years old, a security liability. The original Frugghi/SwiftSH and jakeheis/Shout are similarly stale. None support Swift Concurrency or SPM properly.

| Library | License | SFTP | iOS | Maintained | Dependencies |
|---------|---------|------|-----|------------|-------------|
| **Citadel** | MIT | ✅ | ✅ | Active | SwiftNIO SSH, SwiftCrypto |
| **SwiftNIO SSH** | Apache 2.0 | ❌ | ✅ | Apple-maintained | SwiftNIO, SwiftCrypto |
| **libssh2** | BSD | ✅ | Via xcframework | Active | OpenSSL/mbedTLS |
| NMSSH | MIT | ✅ | ✅ | ❌ Stale | libssh2 + OpenSSL (bundled, outdated) |
| SwiftSH | MIT | ✅ | ✅ | Low activity | libssh2 + OpenSSL |

---

## Secure Enclave gives you hardware-bound SSH keys — but only P-256

The Secure Enclave is the strongest key protection available on iOS. The private key is generated inside the SE hardware, **never exists in main memory**, and cannot be exported, backed up, or transferred to another device. Every signing operation happens on-chip. For SSH, this maps to the `ecdsa-sha2-nistp256` algorithm — the SE exclusively supports **NIST P-256 (secp256r1) ECDSA**. It does not support RSA or Ed25519.

Both Panic's Prompt 3 and Blink Shell ship Secure Enclave SSH key generation today, validating this approach for production use. The implementation uses CryptoKit:

```swift
import CryptoKit

// Generate — private key created inside Secure Enclave
let accessControl = SecAccessControlCreateWithFlags(
    nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    [.privateKeyUsage, .biometryCurrentSet], nil
)!
let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
    accessControl: accessControl
)

// Persist — dataRepresentation is an encrypted blob, usable only on this device
let wrappedKey = privateKey.dataRepresentation  // Store this in Keychain

// Sign SSH challenge — triggers Face ID/Touch ID
let signature = try privateKey.signature(for: sessionHash)

// Export public key — user adds this to server's authorized_keys
let pubKey = privateKey.publicKey.compactRepresentation
```

A critical detail: CryptoKit produces ECDSA signatures in **IEEE P1363 format** (`r || s`, 64 bytes), but SSH wire format expects **DER-encoded ASN.1**. You need a conversion layer. Citadel handles this internally if you provide a `P256.Signing.PrivateKey` for authentication.

**The `dataRepresentation` is not the raw private key** — it's the key encrypted by the SE's hardware-bound wrapping key. Store this blob in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and biometric protection. To reload on next app launch: `try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: storedBlob)`.

The trade-off is per-device key management. Each iPhone or iPad generates its own SE key, and the corresponding public key must be added to every server's `authorized_keys`. For a homelab with 3–10 servers, this is manageable. Consider automating it via an initial `ssh-copy-id`-equivalent flow or a companion script.

---

## Keychain and biometrics protect imported Ed25519 and RSA keys

Most homelab users already have Ed25519 or RSA keys they want to import. Since these key types cannot use the Secure Enclave, the next-best protection is iOS Keychain with biometric-bound access control.

**Storage architecture.** Store the raw private key bytes as a `kSecClassGenericPassword` Keychain item. Set `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to ensure the key is encrypted at rest, only decryptable when the device is unlocked, never included in backups, and never synced to iCloud. For maximum security, use `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` — this automatically **destroys the key if the user removes their device passcode**.

**Biometric gating** is configured via `SecAccessControl`. The two key flags are:

- **`biometryCurrentSet`** — invalidates the key if the user changes their Face ID/Touch ID enrollment (prevents an attacker adding their biometric to access existing keys). Higher security, but the user loses access to stored keys after re-enrolling biometrics.
- **`biometryAny`** — survives biometric enrollment changes. Better UX, slightly weaker security model.

Combine with `.userPresence` to allow device passcode as fallback after biometric failure. When `SecItemCopyMatching` retrieves a biometric-protected item, iOS automatically presents the Face ID/Touch ID prompt — no need to manually call `LAContext.evaluatePolicy`. This is more secure than manual `LAContext` checks, which can be bypassed on jailbroken devices.

**Controlling authentication frequency.** Set `LAContext.touchIDAuthenticationAllowableReuseDuration` to control how often biometric prompts appear. A value of `0` forces authentication on every key access. Values up to **300 seconds** (5 minutes) allow reuse within that window. For an SSH app connecting to multiple servers in sequence, a 30–60 second reuse window prevents prompt fatigue while maintaining security.

**For Ed25519 keys**, after retrieving raw bytes from Keychain, load them directly into CryptoKit: `Curve25519.Signing.PrivateKey(rawRepresentation: keyBytes)`. Signatures from this API produce the standard 64-byte Ed25519 format that SSH expects. For RSA keys, use Security framework's `SecKeyCreateWithData` and `SecKeyCreateSignature`.

**Passphrase encryption as an additional layer.** For users who want defense-in-depth beyond Keychain encryption, derive an encryption key from a user passphrase using `CCKeyDerivationPBKDF` (CommonCrypto, built into iOS) with **HMAC-SHA256 and ≥600,000 iterations**, then encrypt the private key with `AES.GCM.seal()` before storing it. Argon2id is superior but requires a third-party library (`Argon2Swift` via SPM). The pattern: biometric unlocks the key-encryption-key from Keychain; if biometric fails, fall back to passphrase re-derivation.

**Required Info.plist entry**: `NSFaceIDUsageDescription` must contain a string explaining Face ID usage, or biometric authentication will silently fail on Face ID devices.

---

## Transport hardening: modern ciphers, strict TOFU, and homelab-specific defenses

**Cipher suite configuration.** SwiftNIO SSH enforces modern-only algorithms by design — it only supports AES-GCM, Ed25519/ECDSA, and Curve25519 KEX. This is a feature, not a limitation. For a security-focused app, explicitly advertise only these algorithms in order of preference:

- **Key exchange**: `curve25519-sha256`, `ecdh-sha2-nistp256`
- **Ciphers**: `chacha20-poly1305@openssh.com` (if using libssh2), `aes256-gcm@openssh.com`, `aes128-gcm@openssh.com`
- **Host keys**: `ssh-ed25519`, `ecdsa-sha2-nistp256`, `rsa-sha2-512`, `rsa-sha2-256`
- **MACs**: Implicit with AEAD ciphers; `hmac-sha2-512-etm@openssh.com` for CTR fallback

**Explicitly reject** all CBC ciphers, SHA-1 MACs, `ssh-rsa` (SHA-1 signatures), DSA, RC4, 3DES, and `diffie-hellman-group1-sha1`. The Mozilla OpenSSH hardening guidelines and ssh-audit.com provide authoritative algorithm lists. Note that **CVE-2023-48795 (Terrapin)** affects ChaCha20-Poly1305 and CBC-ETM ciphers when strict key exchange is not negotiated — ensure your implementation supports the `strict-kex` extension.

**Host key verification must implement TOFU (Trust On First Use).** On first connection, display the server's host key fingerprint (SHA-256, base64-encoded) and require explicit user acceptance. Store accepted fingerprints in a structured format (JSON or SQLite in `Library/Application Support/`) with hostname, port, key type, full public key, fingerprint, and first-seen date. On subsequent connections, compare silently. **On mismatch, hard-block the connection** with a red warning explaining possible MITM attack — never allow a one-tap override. Require deliberate action like deleting the old key and re-accepting.

**Homelab-specific MITM prevention** goes beyond TOFU:

- **Pre-distribute fingerprints out-of-band.** Generate a QR code on the server containing the host key fingerprint; scan it in the app during setup to skip the TOFU vulnerability window entirely. Encode as a custom URI: `ssh://host:port?fingerprint=SHA256:...&keytype=ssh-ed25519`.
- **Run a personal SSH Certificate Authority.** Generate a CA key (`ssh-keygen -f homelab_ca`), sign each server's host key (`ssh-keygen -s homelab_ca -h -I "server" -n hostname -V +52w host_key.pub`), embed `homelab_ca.pub` in the app. Any server presenting a valid certificate from your CA is trusted automatically — no TOFU, no fingerprint management, and you can rekey or reprovision servers freely.
- **Layer SSH over Tailscale/WireGuard.** Connecting to Tailscale IPs (100.x.y.z) provides an authenticated, encrypted tunnel beneath SSH. This is defense-in-depth, not a replacement for host key verification.
- **Bonjour discovery** (`_ssh._tcp`) can auto-detect homelab servers on the LAN, but mDNS is unauthenticated — any device on the network can impersonate an SSH service. Always verify host keys regardless of discovery method.

---

## iOS sandbox constraints shape your session architecture

**Network access requires no special entitlement** for outbound TCP to internet hosts. However, connecting to **local network addresses** (192.168.x.x, 10.x.x.x) triggers iOS 14+'s Local Network privacy prompt. Declare `NSLocalNetworkUsageDescription` in Info.plist. App Transport Security (ATS) does not apply to raw TCP connections — only HTTP/HTTPS — so no ATS exceptions are needed.

**Background execution is the critical constraint.** iOS suspends apps within seconds of backgrounding, and TCP connections are defuncted. Apple's documentation is explicit: *"The short answer to 'Is it possible to maintain a TCP connection while my app is in the background?' is No."* There is no background mode applicable to SSH. VoIP push (historically abused for persistent connections) now requires CallKit integration and App Review rejects non-VoIP use.

**The practical design pattern** every shipping iOS SSH app uses:

1. When the app backgrounds, call `UIApplication.beginBackgroundTask` to get ~30 seconds of execution time
2. Use that window to send an SSH disconnect, save terminal state (scrollback buffer, cursor position, screen contents)
3. Store connection parameters for fast reconnect
4. When the app foregrounds, re-establish the SSH connection automatically
5. Display "Reconnecting..." UI, then restore the terminal state
6. **Strongly recommend users run `tmux` or `screen`** on the server — the server-side session survives the client disconnect, and the app can reattach on reconnect

**File storage locations:**

| Data | Location | Backed up |
|------|----------|-----------|
| Known hosts / fingerprints | `Library/Application Support/` | Yes |
| Connection profiles | `Library/Application Support/` | Yes |
| Private keys | **iOS Keychain** (not filesystem) | Per Keychain settings |
| Terminal scrollback cache | `Library/Caches/` | No |
| Sensitive data to exclude from backup | Set `isExcludedFromBackup = true` | Forced no |

Use **App Groups** (`group.com.yourapp`) to share connection data between the main app, widgets, and extensions (e.g., a Files provider for SFTP).

---

## Lessons from shipping apps: what Prompt, Blink, and ShellFish got right

Examining five production iOS SSH apps reveals a convergent architecture and several differentiation opportunities.

**Panic's Prompt 3** ($19.99, one-time) uses **libssh2 + OpenSSL** across all Panic products and was among the first to ship Secure Enclave key generation (`ecdsa-sha2-nistp256`). It supports FIDO2/YubiKey via NFC, SSH certificates, and jump hosts. Keys sync via Panic Sync (non-SE keys only). The libssh2 foundation gives it broad server compatibility but carries the C dependency cost.

**Blink Shell** ($19.99/year, GPLv3 open source at [github.com/blinksh/blink](https://github.com/blinksh/blink), ~6.6k stars) uses **libssh + libssh2** and renders via **Chromium's hterm** in a web view. It offers Secure Enclave keys, Mosh for persistent connections over UDP, and a geo-lock feature that drops connections if the device physically moves. The GPLv3 license means you can study the code but not incorporate it into a proprietary app.

**ShellFish** by Anders Borum is notable for the most advanced Secure Enclave integration — it recently added **SSH agent forwarding with SE keys**, requiring biometric approval for each agent signing operation. It also provides a Files.app SFTP provider extension, Apple Watch complications, and Shortcuts integration. Its SSH library is undisclosed but likely custom.

**Termius** (freemium/subscription) is the only app with **SOC 2 Type 2 certification**. It uses a custom SSH implementation built on **Botan + Libsodium**, not libssh2. Its cloud vault uses hybrid E2E encryption with Argon2id password hashing and X25519 + XSalsa20-Poly1305. Penetration test reports are available to business customers but not published publicly.

**a-Shell** (free, BSD-like, [github.com/holzschu/a-shell](https://github.com/holzschu/a-shell)) is an open-source terminal using libssh2 1.11.0 with filesystem-based key storage in `~/Documents/.ssh/` — no Keychain or SE integration. It's the most educational codebase for understanding libssh2 integration on iOS.

**No public security audit exists for any iOS SSH app.** This is a differentiation opportunity — commissioning and publishing an audit would build trust in the homelab community. The Terrapin vulnerability (CVE-2023-48795) affects all apps using libssh2 with ChaCha20-Poly1305 unless patched.

---

## SwiftTerm is the only serious terminal emulator for native iOS

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza (MIT license) is a pure-Swift VT100/xterm-256color terminal emulator used in production by ShellFish and La Terminal. It renders via **CoreText** (hardware-accelerated), supports true color (24-bit), mouse events, Sixel graphics, imgcat inline images, and Unicode with full grapheme cluster handling. Recent benchmarks show **1.2 million escape sequence calls per second**.

The architecture separates concerns cleanly into three layers. The `Terminal` engine class is UI-agnostic — it processes escape sequences and maintains the screen buffer with no I/O dependencies. The `TerminalView` (UIKit `UIView`) renders the buffer and captures keyboard input. Your code bridges SSH and the terminal via the `TerminalViewDelegate` protocol:

```swift
// SSH → Terminal (display server output)
terminal.feed(byteArray: sshChannelData)

// Terminal → SSH (send user keystrokes)
func send(source: TerminalView, data: ArraySlice<UInt8>) {
    sshChannel.write(Data(data))
}
```

For SwiftUI apps, wrap `TerminalView` in a `UIViewRepresentable`. The companion app [SwiftTermApp](https://github.com/migueldeicaza/SwiftTermApp) demonstrates this pattern with SwiftUI + SwiftNIO SSH integration.

**iOS keyboard challenges require a custom accessory toolbar.** The standard iOS keyboard lacks Escape, Ctrl, Tab, and arrow keys. Every shipping SSH app solves this with a `UIView` set as `inputAccessoryView` containing buttons for these keys. SwiftTerm includes a `TerminalAccessory` class for this. Best practices from production apps: Ctrl should support double-tap to lock (for Ctrl+A, Ctrl+C sequences), long-press Ctrl for a shortcuts panel (tmux prefix, common commands), and arrow keys should support both tap and swipe gestures. Hardware keyboards (iPad Magic Keyboard, Bluetooth) should map Cmd→Meta and Option→Alt.

**Terminal resize handling** is critical for iPad multitasking (Split View, Slide Over, Stage Manager). When the `TerminalView` bounds change, calculate new column×row dimensions from `cellDimension` (the width/height of a single character cell), then send an SSH window-change request — the protocol equivalent of `SIGWINCH`. Request the PTY as `xterm-256color` to match SwiftTerm's emulation capabilities.

Alternatives like xterm.js in a WKWebView are technically viable but add JavaScript bridge latency on every keystroke, lose access to native gestures and accessibility APIs, and cannot use the WebGL renderer (iOS WebKit only). Building a custom terminal renderer from scratch using CoreText would take months of work that SwiftTerm already represents.

---

## Recommended architecture and framework integration

Putting it all together, here is the recommended stack for a security-focused homelab SSH terminal:

**Transport layer**: `Network.framework` via SwiftNIO Transport Services (`NIOTSEventLoopGroup` + `NIOTSConnectionBootstrap`). This gives you automatic path selection, Wi-Fi/cellular failover, and proper system integration on iOS. Configure TCP with `noDelay = true` (disable Nagle for interactive SSH), keepalive at 60-second intervals, and a 10-second connection timeout.

**SSH layer**: Citadel (wrapping SwiftNIO SSH) for SSH-2 protocol, authentication, SFTP, and command execution. For the rare legacy server, bundle libssh2 via xcframework as a secondary backend behind a protocol abstraction.

**Key management**: Three tiers of key storage based on security needs. Tier 1: Secure Enclave P-256 keys via `SecureEnclave.P256.Signing.PrivateKey` with biometric gating — maximum security, device-bound. Tier 2: Imported Ed25519/RSA keys in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `biometryCurrentSet`. Tier 3: Passphrase-encrypted keys using PBKDF2 (600K+ iterations) → AES-GCM, with the derived key stored in a biometric-protected Keychain item.

**Terminal**: SwiftTerm `TerminalView` wrapped in `UIViewRepresentable` for SwiftUI, with a custom keyboard accessory toolbar for Ctrl/Esc/Tab/arrows.

**Host verification**: TOFU with known-hosts database in `Library/Application Support/` (JSON or SQLite), plus optional QR code fingerprint import and SSH CA certificate support for zero-TOFU homelab setups.

**Apple frameworks summary**:

- **CryptoKit** — `SecureEnclave.P256.Signing` for SE keys, `Curve25519.Signing` for Ed25519, `AES.GCM`/`ChaChaPoly` for encryption at rest, `HKDF` for key derivation
- **Security.framework** — `SecItemAdd`/`SecItemCopyMatching` for Keychain CRUD, `SecAccessControlCreateWithFlags` for biometric access control, `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave` as alternative SE key API
- **LocalAuthentication** — `LAContext.evaluatePolicy` for explicit biometric checks, `touchIDAuthenticationAllowableReuseDuration` for controlling prompt frequency, `canEvaluatePolicy` to detect biometric hardware
- **Network.framework** — `NWConnection` for TCP, `NWPathMonitor` for connectivity changes and auto-reconnect triggers

## Conclusion

The pure-Swift path — Citadel + SwiftNIO SSH + SwiftTerm + CryptoKit — is now mature enough for production iOS SSH apps, with the important caveat that it only connects to servers supporting modern algorithms (Ed25519/ECDSA, AES-GCM, Curve25519). For a homelab where you control server configuration, this is ideal: harden your `sshd_config` to match the client's algorithm set and gain a zero-C-dependency, fully auditable Swift stack. The Secure Enclave's P-256 limitation is less restrictive than it appears — `ecdsa-sha2-nistp256` is universally supported by OpenSSH servers, and the hardware-bound key model provides security that software Ed25519 keys fundamentally cannot match. The biggest architectural decision is not which library to use but how to handle iOS backgrounding gracefully: invest in fast reconnection logic and tmux/screen integration rather than fighting the platform's suspension model.