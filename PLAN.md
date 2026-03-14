# iOS SSH Terminal App — Claude Code Agent Plan

## Project constraints
- Language: Swift 6, SwiftUI
- Min deployment: iOS 17
- Package manager: SPM only
- No third-party UI libraries
- Security-first at every layer

## Dependencies (SPM)
```
apple/swift-nio-ssh          → SSH-2 protocol core
orlandos-nl/Citadel          → High-level SSH client API
migueldeicaza/SwiftTerm      → Terminal emulator (VT100/xterm-256color)
apple/swift-nio-transport-services → NIOTSEventLoopGroup for Network.framework
```

---

## Phase 1 — Project scaffold

### 1.1 Xcode project setup
- [ ] Create iOS App target, SwiftUI lifecycle, Swift 6 strict concurrency
- [ ] Add SPM dependencies: Citadel, SwiftTerm, NIOTransportServices
- [ ] Configure entitlements: no special entitlements needed for outbound TCP
- [ ] Add `NSFaceIDUsageDescription` and `NSLocalNetworkUsageDescription` to Info.plist
- [ ] Set up folder structure:
  ```
  App/
    Features/
      Connection/
      Terminal/
      KeyManager/
      HostVerification/
    Core/
      SSH/
      Crypto/
      Storage/
    UI/
      Components/
  ```

### 1.2 Base data models
- [ ] `SSHConnectionProfile` — host, port, username, authMethod, lastConnected
- [ ] `SSHAuthMethod` — enum: `.secureEnclaveKey(keyTag)`, `.importedKey(keyID)`, `.password`
- [ ] `SSHHostKey` — hostname, port, keyType, publicKeyData, fingerprint, firstSeenDate
- [ ] `SSHIdentity` — id, label, keyType, publicKeyData, createdAt, storageType

---

## Phase 2 — Crypto and key management

### 2.1 Secure Enclave key manager
- [ ] `SecureEnclaveKeyManager` actor
- [ ] `generateKey(label:) -> SSHIdentity` — creates SE P-256 key with `biometryCurrentSet` + `whenUnlockedThisDeviceOnly`
- [ ] `loadKey(tag:) throws -> SecureEnclave.P256.Signing.PrivateKey`
- [ ] `deleteKey(tag:)`
- [ ] `publicKeyOpenSSHFormat(key:) -> String` — encode P-256 pubkey as `ecdsa-sha2-nistp256` authorized_keys line
- [ ] Handle P1363 → DER signature conversion for SSH wire format

### 2.2 Keychain key manager
- [ ] `KeychainKeyManager` actor
- [ ] `importKey(pemData:label:passphrase:) throws -> SSHIdentity`
  - Parse PEM (Ed25519, RSA-4096, ECDSA)
  - Decrypt passphrase-protected keys via OpenSSH key format parser
  - Store raw private key bytes as `kSecClassGenericPassword` with `biometryCurrentSet`
- [ ] `loadKey(id:) async throws -> Data` — triggers biometric prompt automatically
- [ ] `deleteKey(id:)`
- [ ] `listKeys() -> [SSHIdentity]`

### 2.3 Key manager facade
- [ ] `KeyManager` — unified interface over SE and Keychain managers
- [ ] Protocol `SSHAuthenticatable` — `func authenticate(sessionHash: Data) async throws -> Data`
- [ ] Concrete implementations: `SEKeyAuthenticator`, `ImportedKeyAuthenticator`

### 2.4 Biometric policy
- [ ] Configurable `LAContext` reuse duration (default: 60s)
- [ ] Graceful fallback to device passcode
- [ ] Error handling: `.biometryLockout`, `.biometryNotAvailable`, `.userCancel`

---

## Phase 3 — Host key verification

### 3.1 Known hosts store
- [ ] `KnownHostsStore` actor backed by JSON file in `Library/Application Support/`
- [ ] `lookup(hostname:port:keyType:) -> SSHHostKey?`
- [ ] `trust(hostKey:for hostname:port:)`
- [ ] `revoke(hostname:port:)`
- [ ] Exclude file from iCloud backup via `URLResourceValues.isExcludedFromBackupKey`

### 3.2 TOFU verification engine
- [ ] `HostKeyVerifier` conforming to Citadel's `SSHClientDelegate` / `hostAuthenticationCallback`
- [ ] On first connect: surface fingerprint UI, require explicit user acceptance
- [ ] On reconnect: silent match; hard block + UI warning on mismatch
- [ ] Fingerprint display format: `SHA256:base64` (matches OpenSSH output)

### 3.3 QR fingerprint import
- [ ] Custom URI scheme: `ssh-trust://host:port?fp=SHA256:...&type=ssh-ed25519`
- [ ] AVFoundation QR scanner view
- [ ] Persists to `KnownHostsStore` without network connection needed

---

## Phase 4 — SSH connection layer

### 4.1 SSH session actor
- [ ] `SSHSession` actor wrapping Citadel `SSHClient`
- [ ] `connect(profile:) async throws`
  - Use `NIOTSEventLoopGroup` for Network.framework transport
  - Configure TCP: `noDelay = true`, keepalive every 60s, timeout 10s
  - Pass `HostKeyVerifier` as host auth callback
  - Pass `SSHAuthenticatable` for user auth
- [ ] `disconnect() async`
- [ ] `connectionState: ConnectionState` — `.disconnected`, `.connecting`, `.connected`, `.reconnecting`

### 4.2 PTY and channel management
- [ ] `requestPTY(cols:rows:term:) async throws` — request `xterm-256color`
- [ ] `openShellChannel() async throws -> SSHChannel`
- [ ] `SSHChannel` — async streams for stdin/stdout/stderr
- [ ] Window resize: `sendWindowChange(cols:rows:)` — call on `TerminalView` bounds change

### 4.3 Background/foreground lifecycle
- [ ] `SSHSessionManager` observing `UIApplication` scene phase
- [ ] On background: `beginBackgroundTask`, send SSH disconnect, serialize terminal state
- [ ] On foreground: check `NWPathMonitor` path, auto-reconnect if profile has `autoReconnect = true`
- [ ] Terminal state serialization: cursor position, screen buffer, scrollback (store in `Library/Caches/`)

---

## Phase 5 — Terminal emulator integration

### 5.1 SwiftTerm view wrapper
- [ ] `TerminalViewController: UIViewController` hosting `TerminalView`
- [ ] `SSHTerminalDataSource` conforming to `TerminalViewDelegate`
  - `send(source:data:)` → write to SSH channel stdin
  - `scrolled(source:position:)` → update scroll indicator
  - `setTerminalTitle(source:name:)` → update navigation bar title
- [ ] Feed SSH channel stdout to `terminal.feed(byteArray:)`

### 5.2 SwiftUI bridge
- [ ] `TerminalViewRepresentable: UIViewControllerRepresentable`
- [ ] Coordinator pattern for delegate callbacks
- [ ] Pass `SSHSession` as environment object

### 5.3 Keyboard accessory toolbar
- [ ] Custom `UIView` as `inputAccessoryView`
- [ ] Keys: `Esc`, `Tab`, `Ctrl` (toggle lock mode), `↑ ↓ ← →`, `|`, `~`, `/`
- [ ] Ctrl lock: visual indicator, next key press sends as Ctrl+key
- [ ] Hardware keyboard: `Cmd` → Meta, `Option` → Alt, `Fn+arrows` → Page Up/Down

### 5.4 Terminal resize
- [ ] Override `viewDidLayoutSubviews` — calculate cols/rows from `cellDimension`
- [ ] Debounce resize events (100ms) to avoid spamming during animation
- [ ] Update both local `TerminalView` size and remote SSH window via `sendWindowChange`

---

## Phase 6 — UI

### 6.1 Connection list (root view)
- [ ] `ConnectionListView` — list of `SSHConnectionProfile`
- [ ] Swipe actions: connect, edit, delete
- [ ] Toolbar: add connection, manage keys
- [ ] Recent connections sorted by `lastConnected`

### 6.2 Connection editor
- [ ] `ConnectionEditorView` — host, port, username, auth method picker
- [ ] Auth method picker: SE key (generate new / select existing), imported key, password
- [ ] Test connection button (validates host reachability before saving)
- [ ] Advanced section: keepalive interval, auto-reconnect toggle, custom knownhosts tag

### 6.3 Key manager view
- [ ] `KeyManagerView` — list of `SSHIdentity` with key type badge
- [ ] Add: SE key (generate) or imported key (paste PEM / document picker)
- [ ] Per-key detail: public key display, copy authorized_keys line, QR code of pubkey
- [ ] Delete with biometric confirmation

### 6.4 Host verification sheet
- [ ] Presented modally on first connection to unknown host
- [ ] Show: hostname, port, key type, full fingerprint (SHA256 + hex)
- [ ] Two actions only: Trust & Connect / Cancel
- [ ] On mismatch: full-screen red warning, no quick dismiss

### 6.5 Terminal view
- [ ] Full-screen `TerminalViewRepresentable`
- [ ] Navigation bar: hostname + connection state indicator
- [ ] Pull-down gesture: reveal command palette (tmux shortcuts, copy mode toggle)
- [ ] Long-press selection → copy/paste with system pasteboard

---

## Phase 7 — Storage and persistence

### 7.1 Connection profile store
- [ ] `ProfileStore` actor — JSON file in `Library/Application Support/`
- [ ] Passwords (if used) stored in Keychain, not profile JSON
- [ ] iCloud backup: include profiles, exclude sensitive cached data

### 7.2 App state restoration
- [ ] `SceneDelegate` / `.handlesExternalEvents` for state restoration
- [ ] Restore active connection on relaunch if session was interrupted
- [ ] Do not restore if app was explicitly quit by user

---

## Phase 8 — Security hardening pass

### 8.1 Algorithm enforcement
- [ ] Citadel/SwiftNIO SSH: only modern KEX, ciphers, host key types (already default)
- [ ] Add explicit rejection list for any legacy algorithm negotiation
- [ ] Validate Terrapin (CVE-2023-48795) mitigation is active in SwiftNIO SSH version

### 8.2 Memory hygiene
- [ ] Zero-fill passphrase strings after use (`String` → `[UInt8]`, explicit wipe)
- [ ] Do not log private key material, passphrases, or raw terminal data
- [ ] Disable screenshot/screen recording for key manager views via `UIScreen` + `UITextField.isSecureTextEntry`

### 8.3 Jailbreak resistance (optional, low priority for homelab)
- [ ] Note: SE keys are hardware-bound regardless of jailbreak status
- [ ] Biometric-bound Keychain items: `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` invalidates on passcode removal
- [ ] Do not implement custom jailbreak detection — it provides false confidence

### 8.4 Transport validation
- [ ] Unit tests: verify host key mismatch triggers rejection
- [ ] Unit tests: verify TOFU acceptance persists across cold launch
- [ ] Integration test: connect to local test server, verify cipher negotiation log

---

## Phase 9 — Testing

### 9.1 Unit tests
- [ ] `KeyManagerTests` — SE key generate/load/delete cycle (requires device, not simulator)
- [ ] `KnownHostsStoreTests` — TOFU lookup, trust, revoke, mismatch detection
- [ ] `FingerprintFormatterTests` — SHA256 base64 output matches OpenSSH format
- [ ] `SSHAuthenticatorTests` — mock signing, verify DER output structure

### 9.2 Integration tests (requires local SSH server — use Docker)
- [ ] `SSHConnectionTests` — connect, authenticate (Ed25519 + SE key), run command, disconnect
- [ ] `HostKeyVerificationTests` — first connect accepts, second connect matches, changed key blocks
- [ ] `ReconnectionTests` — simulate background/foreground cycle, verify state restoration

### 9.3 Local test server setup
```yaml
# docker-compose.yml
services:
  sshd:
    image: lscr.io/linuxserver/openssh-server
    environment:
      - PUBLIC_KEY=<test_ed25519_pubkey>
      - USER_NAME=testuser
    ports:
      - "2222:2222"
```

---

## Execution order

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 (core loop complete)
                                  ↓
                              Phase 5 (terminal)
                                  ↓
                              Phase 6 (UI shells)
                                  ↓
                  Phase 7 + Phase 8 (storage + hardening)
                                  ↓
                              Phase 9 (tests)
```

Each phase should end with a buildable, runnable state. Phase 4 completion = first working SSH connection from the app. That is the most important milestone — everything else is layered on top.
