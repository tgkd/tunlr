# iOS SSH Terminal App — Full Implementation Plan

## Overview

Build a security-focused iOS SSH terminal app using Swift 6/SwiftUI targeting iOS 17+. The app uses Citadel (SwiftNIO SSH) for SSH-2 protocol, SwiftTerm for terminal emulation, Secure Enclave P-256 keys for hardware-bound authentication, and iOS Keychain with biometric gating for imported keys. No third-party UI libraries, SPM only.

## Context

- Files involved: Greenfield project — all files will be created
- Source specification: `PLAN.md` (9 phases), `research.md` (technical deep-dive)
- Dependencies (SPM): `apple/swift-nio-ssh`, `orlandos-nl/Citadel`, `migueldeicaza/SwiftTerm`, `apple/swift-nio-transport-services`
- Related patterns: SwiftUI lifecycle, actor-based concurrency (Swift 6 strict), UIViewControllerRepresentable for SwiftTerm

## Development Approach

- **Testing approach**: Regular (code first, then tests) — Secure Enclave and SSH tests require device/server
- Complete each task fully before moving to the next
- Each phase should end with a buildable, runnable state
- Phase 4 completion = first working SSH connection (key milestone)
- **CRITICAL: every task MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**

## Implementation Steps

### Task 1: Xcode project scaffold and SPM dependencies

**Files:**
- Create: `DivineMarssh.xcodeproj` (Xcode project)
- Create: `Package.swift` or Xcode SPM integration
- Create: `App/DivineMarsshApp.swift`
- Create: `App/ContentView.swift`
- Create: `App/Info.plist`
- Create: folder structure under `App/` (Features/, Core/, UI/)

- [x] Create iOS App target with SwiftUI lifecycle, Swift 6 strict concurrency enabled
- [x] Add SPM dependencies: Citadel, SwiftTerm, NIOTransportServices
- [x] Configure Info.plist: `NSFaceIDUsageDescription`, `NSLocalNetworkUsageDescription`
- [x] Set up folder structure: `App/Features/{Connection,Terminal,KeyManager,HostVerification}/`, `App/Core/{SSH,Crypto,Storage}/`, `App/UI/Components/`
- [x] Verify project builds and launches on simulator with empty SwiftUI view
- [x] Write a basic build-verification test that asserts the app entry point exists

### Task 2: Base data models and profile store

**Files:**
- Create: `App/Core/Storage/Models/SSHConnectionProfile.swift`
- Create: `App/Core/Storage/Models/SSHAuthMethod.swift`
- Create: `App/Core/Storage/Models/SSHHostKey.swift`
- Create: `App/Core/Storage/Models/SSHIdentity.swift`
- Create: `App/Core/Storage/ProfileStore.swift`
- Create: `Tests/StorageTests/ProfileStoreTests.swift`
- Create: `Tests/StorageTests/ModelTests.swift`

- [x] Define `SSHConnectionProfile` — host, port, username, authMethod, lastConnected, autoReconnect
- [x] Define `SSHAuthMethod` enum — `.secureEnclaveKey(keyTag)`, `.importedKey(keyID)`, `.password`
- [x] Define `SSHHostKey` — hostname, port, keyType, publicKeyData, fingerprint, firstSeenDate
- [x] Define `SSHIdentity` — id, label, keyType, publicKeyData, createdAt, storageType
- [x] All models: `Codable`, `Sendable`, `Identifiable`
- [x] Implement `ProfileStore` actor — JSON file in `Library/Application Support/`
- [x] ProfileStore: CRUD operations, passwords stored in Keychain (not JSON), iCloud backup inclusion for profiles
- [x] Write tests for model encoding/decoding round-trips
- [x] Write tests for ProfileStore CRUD operations (create, read, update, delete)
- [x] Run project test suite — must pass before task 3

### Task 3: Secure Enclave key manager

**Files:**
- Create: `App/Core/Crypto/SecureEnclaveKeyManager.swift`
- Create: `Tests/CryptoTests/SecureEnclaveKeyManagerTests.swift`

- [ ] Implement `SecureEnclaveKeyManager` actor
- [ ] `generateKey(label:) -> SSHIdentity` — creates SE P-256 key with `biometryCurrentSet` + `whenUnlockedThisDeviceOnly`
- [ ] `loadKey(tag:) throws -> SecureEnclave.P256.Signing.PrivateKey` — reload from stored `dataRepresentation`
- [ ] `deleteKey(tag:)` — remove from Keychain
- [ ] `publicKeyOpenSSHFormat(key:) -> String` — encode P-256 pubkey as `ecdsa-sha2-nistp256` authorized_keys line
- [ ] Store `dataRepresentation` blob in Keychain with biometric protection
- [ ] Handle P1363 to DER signature conversion for SSH wire format (or verify Citadel handles this)
- [ ] Write tests for key generation, load, delete cycle (note: SE tests require physical device)
- [ ] Write tests for public key OpenSSH format output
- [ ] Run project test suite — must pass before task 4

### Task 4: Keychain key manager and biometric policy

**Files:**
- Create: `App/Core/Crypto/KeychainKeyManager.swift`
- Create: `App/Core/Crypto/BiometricPolicy.swift`
- Create: `Tests/CryptoTests/KeychainKeyManagerTests.swift`

- [ ] Implement `KeychainKeyManager` actor
- [ ] `importKey(pemData:label:passphrase:) throws -> SSHIdentity` — parse PEM (Ed25519, RSA-4096, ECDSA), decrypt passphrase-protected keys, store as `kSecClassGenericPassword` with `biometryCurrentSet`
- [ ] `loadKey(id:) async throws -> Data` — triggers biometric prompt automatically via Keychain
- [ ] `deleteKey(id:)`, `listKeys() -> [SSHIdentity]`
- [ ] Implement `BiometricPolicy` — configurable `LAContext` reuse duration (default 60s), graceful fallback to passcode, error handling for `.biometryLockout`, `.biometryNotAvailable`, `.userCancel`
- [ ] Write tests for key import/load/delete with mock Keychain (simulator-compatible)
- [ ] Write tests for PEM parsing (Ed25519, RSA, ECDSA formats)
- [ ] Run project test suite — must pass before task 5

### Task 5: Key manager facade

**Files:**
- Create: `App/Core/Crypto/KeyManager.swift`
- Create: `App/Core/Crypto/SSHAuthenticatable.swift`
- Create: `App/Core/Crypto/SEKeyAuthenticator.swift`
- Create: `App/Core/Crypto/ImportedKeyAuthenticator.swift`
- Create: `Tests/CryptoTests/KeyManagerTests.swift`

- [ ] Define protocol `SSHAuthenticatable` — `func authenticate(sessionHash: Data) async throws -> Data`
- [ ] Implement `SEKeyAuthenticator` conforming to `SSHAuthenticatable`
- [ ] Implement `ImportedKeyAuthenticator` conforming to `SSHAuthenticatable`
- [ ] Implement `KeyManager` as unified facade over `SecureEnclaveKeyManager` and `KeychainKeyManager`
- [ ] Write tests with mock authenticators verifying facade routing
- [ ] Write tests for DER signature output structure
- [ ] Run project test suite — must pass before task 6

### Task 6: Known hosts store and TOFU verification

**Files:**
- Create: `App/Core/Storage/KnownHostsStore.swift`
- Create: `App/Features/HostVerification/HostKeyVerifier.swift`
- Create: `App/Features/HostVerification/FingerprintFormatter.swift`
- Create: `Tests/HostVerificationTests/KnownHostsStoreTests.swift`
- Create: `Tests/HostVerificationTests/FingerprintFormatterTests.swift`

- [ ] Implement `KnownHostsStore` actor — JSON file in `Library/Application Support/`
- [ ] `lookup(hostname:port:keyType:) -> SSHHostKey?`, `trust(hostKey:for:port:)`, `revoke(hostname:port:)`
- [ ] Exclude file from iCloud backup via `isExcludedFromBackupKey`
- [ ] Implement `FingerprintFormatter` — SHA256 base64 format matching OpenSSH output
- [ ] Implement `HostKeyVerifier` conforming to Citadel's host authentication callback
- [ ] First connect: return `.needsUserApproval(fingerprint)` for UI to handle
- [ ] Reconnect: silent match on known key; hard block on mismatch
- [ ] Write tests for KnownHostsStore CRUD and mismatch detection
- [ ] Write tests for fingerprint formatting (SHA256 base64 matches OpenSSH)
- [ ] Run project test suite — must pass before task 7

### Task 7: SSH session actor and channel management

**Files:**
- Create: `App/Core/SSH/SSHSession.swift`
- Create: `App/Core/SSH/ConnectionState.swift`
- Create: `Tests/SSHTests/SSHSessionTests.swift`

- [ ] Define `ConnectionState` enum — `.disconnected`, `.connecting`, `.connected`, `.reconnecting`
- [ ] Implement `SSHSession` actor wrapping Citadel `SSHClient`
- [ ] `connect(profile:) async throws` — use `NIOTSEventLoopGroup`, configure TCP (`noDelay`, keepalive 60s, timeout 10s), pass `HostKeyVerifier` and `SSHAuthenticatable`
- [ ] `disconnect() async`
- [ ] `requestPTY(cols:rows:term:) async throws` — request `xterm-256color`
- [ ] `openShellChannel() async throws` — async streams for stdin/stdout/stderr
- [ ] `sendWindowChange(cols:rows:)` — send on terminal resize
- [ ] Expose `connectionState` as async stream or published property
- [ ] Write tests with mock SSH client verifying state transitions
- [ ] Write tests for PTY request parameters
- [ ] Run project test suite — must pass before task 8

### Task 8: SwiftTerm integration and SwiftUI bridge

**Files:**
- Create: `App/Features/Terminal/TerminalViewController.swift`
- Create: `App/Features/Terminal/SSHTerminalDataSource.swift`
- Create: `App/Features/Terminal/TerminalViewRepresentable.swift`
- Create: `Tests/TerminalTests/SSHTerminalDataSourceTests.swift`

- [ ] Implement `TerminalViewController: UIViewController` hosting SwiftTerm `TerminalView`
- [ ] Implement `SSHTerminalDataSource` conforming to `TerminalViewDelegate`
  - `send(source:data:)` — write to SSH channel stdin
  - `scrolled(source:position:)` — update scroll indicator
  - `setTerminalTitle(source:name:)` — update navigation bar title
- [ ] Feed SSH channel stdout to `terminal.feed(byteArray:)`
- [ ] Implement `TerminalViewRepresentable: UIViewControllerRepresentable` with Coordinator
- [ ] Terminal resize: calculate cols/rows from `cellDimension` in `viewDidLayoutSubviews`, debounce 100ms, update local size + remote SSH window
- [ ] Write tests for data source delegate method routing
- [ ] Run project test suite — must pass before task 9

### Task 9: Keyboard accessory toolbar

**Files:**
- Create: `App/Features/Terminal/KeyboardAccessoryView.swift`
- Create: `Tests/TerminalTests/KeyboardAccessoryTests.swift`

- [ ] Implement custom `UIView` as `inputAccessoryView`
- [ ] Keys: Esc, Tab, Ctrl (toggle lock mode), arrow keys, pipe, tilde, slash
- [ ] Ctrl lock mode: visual indicator, next key press sends as Ctrl+key
- [ ] Hardware keyboard mapping: Cmd to Meta, Option to Alt, Fn+arrows to Page Up/Down
- [ ] Wire up to `TerminalViewController`
- [ ] Write tests for key mapping logic and Ctrl lock toggle
- [ ] Run project test suite — must pass before task 10

### Task 10: Connection list and editor views

**Files:**
- Create: `App/Features/Connection/ConnectionListView.swift`
- Create: `App/Features/Connection/ConnectionEditorView.swift`
- Create: `App/Features/Connection/ConnectionViewModel.swift`
- Create: `Tests/ConnectionTests/ConnectionViewModelTests.swift`

- [ ] Implement `ConnectionListView` — list of `SSHConnectionProfile` sorted by `lastConnected`
- [ ] Swipe actions: connect, edit, delete
- [ ] Toolbar: add connection, manage keys
- [ ] Implement `ConnectionEditorView` — host, port, username, auth method picker
- [ ] Auth method picker: SE key (generate/select), imported key, password
- [ ] Test connection button (validates host reachability)
- [ ] Advanced section: keepalive interval, auto-reconnect toggle
- [ ] Implement `ConnectionViewModel` with business logic
- [ ] Write tests for ConnectionViewModel (profile CRUD, validation)
- [ ] Run project test suite — must pass before task 11

### Task 11: Key manager and host verification views

**Files:**
- Create: `App/Features/KeyManager/KeyManagerView.swift`
- Create: `App/Features/KeyManager/KeyDetailView.swift`
- Create: `App/Features/KeyManager/KeyManagerViewModel.swift`
- Create: `App/Features/HostVerification/HostVerificationSheet.swift`
- Create: `App/Features/HostVerification/HostKeyMismatchWarning.swift`
- Create: `Tests/KeyManagerTests/KeyManagerViewModelTests.swift`

- [ ] Implement `KeyManagerView` — list of `SSHIdentity` with key type badges
- [ ] Add key: SE key generation or imported key (paste PEM / document picker)
- [ ] `KeyDetailView` — public key display, copy authorized_keys line, QR code of pubkey
- [ ] Delete with biometric confirmation
- [ ] Implement `HostVerificationSheet` — modal for first connection: hostname, port, key type, full fingerprint (SHA256 + hex), Trust & Connect / Cancel
- [ ] Implement `HostKeyMismatchWarning` — full-screen red warning, no quick dismiss
- [ ] Write tests for KeyManagerViewModel (list, add, delete flows)
- [ ] Run project test suite — must pass before task 12

### Task 12: Terminal view and session lifecycle

**Files:**
- Create: `App/Features/Terminal/TerminalScreen.swift`
- Create: `App/Core/SSH/SSHSessionManager.swift`
- Create: `Tests/SSHTests/SSHSessionManagerTests.swift`

- [ ] Implement `TerminalScreen` — full-screen `TerminalViewRepresentable`
- [ ] Navigation bar: hostname + connection state indicator
- [ ] Pull-down gesture: reveal command palette (tmux shortcuts, copy mode toggle)
- [ ] Long-press selection with system pasteboard copy/paste
- [ ] Implement `SSHSessionManager` observing `UIApplication` scene phase
- [ ] On background: `beginBackgroundTask`, send SSH disconnect, serialize terminal state (cursor, screen buffer, scrollback to `Library/Caches/`)
- [ ] On foreground: check `NWPathMonitor`, auto-reconnect if profile has `autoReconnect = true`
- [ ] Write tests for SSHSessionManager state transitions (background/foreground cycle)
- [ ] Run project test suite — must pass before task 13

### Task 13: App state restoration and storage finalization

**Files:**
- Create: `App/Core/Storage/TerminalStateCache.swift`
- Modify: `App/DivineMarsshApp.swift`
- Create: `Tests/StorageTests/TerminalStateCacheTests.swift`

- [ ] Implement `TerminalStateCache` — serialize/deserialize terminal state to `Library/Caches/`
- [ ] App state restoration: restore active connection on relaunch if session was interrupted
- [ ] Do not restore if app was explicitly quit by user
- [ ] Verify passwords stored in Keychain (not profile JSON)
- [ ] Write tests for terminal state serialization round-trip
- [ ] Run project test suite — must pass before task 14

### Task 14: Security hardening

**Files:**
- Create: `App/Core/SSH/AlgorithmPolicy.swift`
- Create: `App/Core/Crypto/MemoryHygiene.swift`
- Modify: `App/Core/SSH/SSHSession.swift`
- Modify: `App/Features/KeyManager/KeyManagerView.swift`
- Create: `Tests/SecurityTests/AlgorithmPolicyTests.swift`
- Create: `Tests/SecurityTests/MemoryHygieneTests.swift`

- [ ] Algorithm enforcement: configure Citadel/SwiftNIO SSH for modern-only KEX, ciphers, host key types
- [ ] Add explicit rejection for legacy algorithm negotiation
- [ ] Validate Terrapin (CVE-2023-48795) mitigation is active in SwiftNIO SSH version
- [ ] Memory hygiene: use `[UInt8]` instead of `String` for passphrases, zero-fill after use
- [ ] Disable logging of private key material, passphrases, raw terminal data
- [ ] Disable screenshot/screen recording for key manager views
- [ ] Write tests verifying algorithm policy rejects legacy ciphers
- [ ] Write tests for memory zeroing behavior
- [ ] Run project test suite — must pass before task 15

### Task 15: QR fingerprint import

**Files:**
- Create: `App/Features/HostVerification/QRFingerprintScanner.swift`
- Create: `App/Features/HostVerification/FingerprintURIParser.swift`
- Create: `Tests/HostVerificationTests/FingerprintURIParserTests.swift`

- [ ] Define custom URI scheme: `ssh-trust://host:port?fp=SHA256:...&type=ssh-ed25519`
- [ ] Implement `FingerprintURIParser` for the URI format
- [ ] Implement `QRFingerprintScanner` — AVFoundation QR scanner view
- [ ] Persist scanned fingerprint to `KnownHostsStore` (no network connection needed)
- [ ] Write tests for URI parsing (valid and malformed inputs)
- [ ] Run project test suite — must pass before task 16

### Task 16: Integration tests and test server

**Files:**
- Create: `docker-compose.yml`
- Create: `Tests/IntegrationTests/SSHConnectionTests.swift`
- Create: `Tests/IntegrationTests/HostKeyVerificationTests.swift`
- Create: `Tests/IntegrationTests/ReconnectionTests.swift`

- [ ] Set up Docker test SSH server (linuxserver/openssh-server on port 2222)
- [ ] Write integration test: connect, authenticate (Ed25519), run command, disconnect
- [ ] Write integration test: first connect accepts, second connect matches, changed key blocks
- [ ] Write integration test: simulate background/foreground cycle, verify state restoration
- [ ] Run full integration test suite
- [ ] Run project test suite — must pass before task 17

### Task 17: Verify acceptance criteria

- [ ] Manual test: generate SE key, add to test server, connect, run commands in terminal
- [ ] Manual test: import Ed25519 key, connect to server, verify biometric prompt
- [ ] Manual test: connect to unknown host, verify fingerprint prompt appears
- [ ] Manual test: background app, foreground, verify reconnection
- [ ] Manual test: verify keyboard accessory bar works (Ctrl, Esc, Tab, arrows)
- [ ] Run full test suite (`xcodebuild test`)
- [ ] Run SwiftLint or Swift compiler warnings check
- [ ] Verify test coverage meets 80%+

### Task 18: Update documentation

- [ ] Update README.md with project description, build instructions, and usage
- [ ] Update CLAUDE.md if internal patterns changed
- [ ] Move this plan to `docs/plans/completed/`
