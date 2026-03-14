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

- [x] Implement `SecureEnclaveKeyManager` actor
- [x] `generateKey(label:) -> SSHIdentity` — creates SE P-256 key with `biometryCurrentSet` + `whenUnlockedThisDeviceOnly`
- [x] `loadKey(tag:) throws -> SecureEnclave.P256.Signing.PrivateKey` — reload from stored `dataRepresentation`
- [x] `deleteKey(tag:)` — remove from Keychain
- [x] `publicKeyOpenSSHFormat(key:) -> String` — encode P-256 pubkey as `ecdsa-sha2-nistp256` authorized_keys line
- [x] Store `dataRepresentation` blob in Keychain with biometric protection
- [x] Handle P1363 to DER signature conversion for SSH wire format (or verify Citadel handles this)
- [x] Write tests for key generation, load, delete cycle (note: SE tests require physical device)
- [x] Write tests for public key OpenSSH format output
- [x] Run project test suite — must pass before task 4

### Task 4: Keychain key manager and biometric policy

**Files:**
- Create: `App/Core/Crypto/KeychainKeyManager.swift`
- Create: `App/Core/Crypto/BiometricPolicy.swift`
- Create: `Tests/CryptoTests/KeychainKeyManagerTests.swift`

- [x] Implement `KeychainKeyManager` actor
- [x] `importKey(pemData:label:passphrase:) throws -> SSHIdentity` — parse PEM (Ed25519, RSA-4096, ECDSA), decrypt passphrase-protected keys, store as `kSecClassGenericPassword` with `biometryCurrentSet`
- [x] `loadKey(id:) async throws -> Data` — triggers biometric prompt automatically via Keychain
- [x] `deleteKey(id:)`, `listKeys() -> [SSHIdentity]`
- [x] Implement `BiometricPolicy` — configurable `LAContext` reuse duration (default 60s), graceful fallback to passcode, error handling for `.biometryLockout`, `.biometryNotAvailable`, `.userCancel`
- [x] Write tests for key import/load/delete with mock Keychain (simulator-compatible)
- [x] Write tests for PEM parsing (Ed25519, RSA, ECDSA formats)
- [x] Run project test suite — must pass before task 5

### Task 5: Key manager facade

**Files:**
- Create: `App/Core/Crypto/KeyManager.swift`
- Create: `App/Core/Crypto/SSHAuthenticatable.swift`
- Create: `App/Core/Crypto/SEKeyAuthenticator.swift`
- Create: `App/Core/Crypto/ImportedKeyAuthenticator.swift`
- Create: `Tests/CryptoTests/KeyManagerTests.swift`

- [x] Define protocol `SSHAuthenticatable` — `func authenticate(sessionHash: Data) async throws -> Data`
- [x] Implement `SEKeyAuthenticator` conforming to `SSHAuthenticatable`
- [x] Implement `ImportedKeyAuthenticator` conforming to `SSHAuthenticatable`
- [x] Implement `KeyManager` as unified facade over `SecureEnclaveKeyManager` and `KeychainKeyManager`
- [x] Write tests with mock authenticators verifying facade routing
- [x] Write tests for DER signature output structure
- [x] Run project test suite — must pass before task 6

### Task 6: Known hosts store and TOFU verification

**Files:**
- Create: `App/Core/Storage/KnownHostsStore.swift`
- Create: `App/Features/HostVerification/HostKeyVerifier.swift`
- Create: `App/Features/HostVerification/FingerprintFormatter.swift`
- Create: `Tests/HostVerificationTests/KnownHostsStoreTests.swift`
- Create: `Tests/HostVerificationTests/FingerprintFormatterTests.swift`

- [x] Implement `KnownHostsStore` actor — JSON file in `Library/Application Support/`
- [x] `lookup(hostname:port:keyType:) -> SSHHostKey?`, `trust(hostKey:for:port:)`, `revoke(hostname:port:)`
- [x] Exclude file from iCloud backup via `isExcludedFromBackupKey`
- [x] Implement `FingerprintFormatter` — SHA256 base64 format matching OpenSSH output
- [x] Implement `HostKeyVerifier` conforming to Citadel's host authentication callback
- [x] First connect: return `.needsUserApproval(fingerprint)` for UI to handle
- [x] Reconnect: silent match on known key; hard block on mismatch
- [x] Write tests for KnownHostsStore CRUD and mismatch detection
- [x] Write tests for fingerprint formatting (SHA256 base64 matches OpenSSH)
- [x] Run project test suite — must pass before task 7

### Task 7: SSH session actor and channel management

**Files:**
- Create: `App/Core/SSH/SSHSession.swift`
- Create: `App/Core/SSH/ConnectionState.swift`
- Create: `Tests/SSHTests/SSHSessionTests.swift`

- [x] Define `ConnectionState` enum — `.disconnected`, `.connecting`, `.connected`, `.reconnecting`
- [x] Implement `SSHSession` actor wrapping Citadel `SSHClient`
- [x] `connect(profile:) async throws` — use `NIOTSEventLoopGroup`, configure TCP (`noDelay`, keepalive 60s, timeout 10s), pass `HostKeyVerifier` and `SSHAuthenticatable`
- [x] `disconnect() async`
- [x] `requestPTY(cols:rows:term:) async throws` — request `xterm-256color`
- [x] `openShellChannel() async throws` — async streams for stdin/stdout/stderr
- [x] `sendWindowChange(cols:rows:)` — send on terminal resize
- [x] Expose `connectionState` as async stream or published property
- [x] Write tests with mock SSH client verifying state transitions
- [x] Write tests for PTY request parameters
- [x] Run project test suite — must pass before task 8

### Task 8: SwiftTerm integration and SwiftUI bridge

**Files:**
- Create: `App/Features/Terminal/TerminalViewController.swift`
- Create: `App/Features/Terminal/SSHTerminalDataSource.swift`
- Create: `App/Features/Terminal/TerminalViewRepresentable.swift`
- Create: `Tests/TerminalTests/SSHTerminalDataSourceTests.swift`

- [x] Implement `TerminalViewController: UIViewController` hosting SwiftTerm `TerminalView`
- [x] Implement `SSHTerminalDataSource` conforming to `TerminalViewDelegate`
  - `send(source:data:)` — write to SSH channel stdin
  - `scrolled(source:position:)` — update scroll indicator
  - `setTerminalTitle(source:name:)` — update navigation bar title
- [x] Feed SSH channel stdout to `terminal.feed(byteArray:)`
- [x] Implement `TerminalViewRepresentable: UIViewControllerRepresentable` with Coordinator
- [x] Terminal resize: calculate cols/rows from `cellDimension` in `viewDidLayoutSubviews`, debounce 100ms, update local size + remote SSH window
- [x] Write tests for data source delegate method routing
- [x] Run project test suite — must pass before task 9

### Task 9: Keyboard accessory toolbar

**Files:**
- Create: `App/Features/Terminal/KeyboardAccessoryView.swift`
- Create: `Tests/TerminalTests/KeyboardAccessoryTests.swift`

- [x] Implement custom `UIView` as `inputAccessoryView`
- [x] Keys: Esc, Tab, Ctrl (toggle lock mode), arrow keys, pipe, tilde, slash
- [x] Ctrl lock mode: visual indicator, next key press sends as Ctrl+key
- [x] Hardware keyboard mapping: Cmd to Meta, Option to Alt, Fn+arrows to Page Up/Down
- [x] Wire up to `TerminalViewController`
- [x] Write tests for key mapping logic and Ctrl lock toggle
- [x] Run project test suite — must pass before task 10

### Task 10: Connection list and editor views

**Files:**
- Create: `App/Features/Connection/ConnectionListView.swift`
- Create: `App/Features/Connection/ConnectionEditorView.swift`
- Create: `App/Features/Connection/ConnectionViewModel.swift`
- Create: `Tests/ConnectionTests/ConnectionViewModelTests.swift`

- [x] Implement `ConnectionListView` — list of `SSHConnectionProfile` sorted by `lastConnected`
- [x] Swipe actions: connect, edit, delete
- [x] Toolbar: add connection, manage keys
- [x] Implement `ConnectionEditorView` — host, port, username, auth method picker
- [x] Auth method picker: SE key (generate/select), imported key, password
- [x] Test connection button (validates host reachability)
- [x] Advanced section: keepalive interval, auto-reconnect toggle
- [x] Implement `ConnectionViewModel` with business logic
- [x] Write tests for ConnectionViewModel (profile CRUD, validation)
- [x] Run project test suite — must pass before task 11

### Task 11: Key manager and host verification views

**Files:**
- Create: `App/Features/KeyManager/KeyManagerView.swift`
- Create: `App/Features/KeyManager/KeyDetailView.swift`
- Create: `App/Features/KeyManager/KeyManagerViewModel.swift`
- Create: `App/Features/HostVerification/HostVerificationSheet.swift`
- Create: `App/Features/HostVerification/HostKeyMismatchWarning.swift`
- Create: `Tests/KeyManagerTests/KeyManagerViewModelTests.swift`

- [x] Implement `KeyManagerView` — list of `SSHIdentity` with key type badges
- [x] Add key: SE key generation or imported key (paste PEM / document picker)
- [x] `KeyDetailView` — public key display, copy authorized_keys line, QR code of pubkey
- [x] Delete with biometric confirmation
- [x] Implement `HostVerificationSheet` — modal for first connection: hostname, port, key type, full fingerprint (SHA256 + hex), Trust & Connect / Cancel
- [x] Implement `HostKeyMismatchWarning` — full-screen red warning, no quick dismiss
- [x] Write tests for KeyManagerViewModel (list, add, delete flows)
- [x] Run project test suite — must pass before task 12

### Task 12: Terminal view and session lifecycle

**Files:**
- Create: `App/Features/Terminal/TerminalScreen.swift`
- Create: `App/Core/SSH/SSHSessionManager.swift`
- Create: `Tests/SSHTests/SSHSessionManagerTests.swift`

- [x] Implement `TerminalScreen` — full-screen `TerminalViewRepresentable`
- [x] Navigation bar: hostname + connection state indicator
- [x] Pull-down gesture: reveal command palette (tmux shortcuts, copy mode toggle)
- [x] Long-press selection with system pasteboard copy/paste
- [x] Implement `SSHSessionManager` observing `UIApplication` scene phase
- [x] On background: `beginBackgroundTask`, send SSH disconnect, serialize terminal state (cursor, screen buffer, scrollback to `Library/Caches/`)
- [x] On foreground: check `NWPathMonitor`, auto-reconnect if profile has `autoReconnect = true`
- [x] Write tests for SSHSessionManager state transitions (background/foreground cycle)
- [x] Run project test suite — must pass before task 13

### Task 13: App state restoration and storage finalization

**Files:**
- Create: `App/Core/Storage/TerminalStateCache.swift`
- Modify: `App/DivineMarsshApp.swift`
- Create: `Tests/StorageTests/TerminalStateCacheTests.swift`

- [x] Implement `TerminalStateCache` — serialize/deserialize terminal state to `Library/Caches/`
- [x] App state restoration: restore active connection on relaunch if session was interrupted
- [x] Do not restore if app was explicitly quit by user
- [x] Verify passwords stored in Keychain (not profile JSON)
- [x] Write tests for terminal state serialization round-trip
- [x] Run project test suite — must pass before task 14

### Task 14: Security hardening

**Files:**
- Create: `App/Core/SSH/AlgorithmPolicy.swift`
- Create: `App/Core/Crypto/MemoryHygiene.swift`
- Modify: `App/Core/SSH/SSHSession.swift`
- Modify: `App/Features/KeyManager/KeyManagerView.swift`
- Create: `Tests/SecurityTests/AlgorithmPolicyTests.swift`
- Create: `Tests/SecurityTests/MemoryHygieneTests.swift`

- [x] Algorithm enforcement: configure Citadel/SwiftNIO SSH for modern-only KEX, ciphers, host key types
- [x] Add explicit rejection for legacy algorithm negotiation
- [x] Validate Terrapin (CVE-2023-48795) mitigation is active in SwiftNIO SSH version
- [x] Memory hygiene: use `[UInt8]` instead of `String` for passphrases, zero-fill after use
- [x] Disable logging of private key material, passphrases, raw terminal data
- [x] Disable screenshot/screen recording for key manager views
- [x] Write tests verifying algorithm policy rejects legacy ciphers
- [x] Write tests for memory zeroing behavior
- [x] Run project test suite — must pass before task 15

### Task 15: QR fingerprint import

**Files:**
- Create: `App/Features/HostVerification/QRFingerprintScanner.swift`
- Create: `App/Features/HostVerification/FingerprintURIParser.swift`
- Create: `Tests/HostVerificationTests/FingerprintURIParserTests.swift`

- [x] Define custom URI scheme: `ssh-trust://host:port?fp=SHA256:...&type=ssh-ed25519`
- [x] Implement `FingerprintURIParser` for the URI format
- [x] Implement `QRFingerprintScanner` — AVFoundation QR scanner view
- [x] Persist scanned fingerprint to `KnownHostsStore` (no network connection needed)
- [x] Write tests for URI parsing (valid and malformed inputs)
- [x] Run project test suite — must pass before task 16

### Task 16: Integration tests and test server

**Files:**
- Create: `docker-compose.yml`
- Create: `Tests/IntegrationTests/SSHConnectionTests.swift`
- Create: `Tests/IntegrationTests/HostKeyVerificationTests.swift`
- Create: `Tests/IntegrationTests/ReconnectionTests.swift`

- [x] Set up Docker test SSH server (linuxserver/openssh-server on port 2222)
- [x] Write integration test: connect, authenticate (Ed25519), run command, disconnect
- [x] Write integration test: first connect accepts, second connect matches, changed key blocks
- [x] Write integration test: simulate background/foreground cycle, verify state restoration
- [x] Run full integration test suite
- [x] Run project test suite — must pass before task 17

### Task 17: Verify acceptance criteria

- [x] Manual test: generate SE key, add to test server, connect, run commands in terminal
- [x] Manual test: import Ed25519 key, connect to server, verify biometric prompt
- [x] Manual test: connect to unknown host, verify fingerprint prompt appears
- [x] Manual test: background app, foreground, verify reconnection
- [x] Manual test: verify keyboard accessory bar works (Ctrl, Esc, Tab, arrows)
- [x] Run full test suite (`xcodebuild test`)
- [x] Run SwiftLint or Swift compiler warnings check
- [x] Verify test coverage meets 80%+

### Task 18: Update documentation

- [x] Update README.md with project description, build instructions, and usage
- [x] Update CLAUDE.md if internal patterns changed
- [x] Move this plan to `docs/plans/completed/`
