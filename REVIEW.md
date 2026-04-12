# tunlr (DivineMarssh) — Architecture & Security Review

**Date:** 2026-04-12
**Scope:** Full codebase review — architecture, code structure, security
**Commit:** `b003a08`

---

## Executive Summary

tunlr is a well-architected iOS SSH terminal client built with Swift 6 strict concurrency. The codebase demonstrates strong separation of concerns, thorough use of protocol-based dependency injection, and modern async/await patterns throughout. Security fundamentals are solid — Secure Enclave key storage, AES-GCM-only cipher policy, Keychain-backed credentials, and TOFU host verification infrastructure.

However, **the TOFU host key verification is completely bypassed** in production code (`approvalHandler: { _ in true }`), which auto-trusts every server on first connection without user confirmation. This is the most critical finding. Additional concerns include immutable password strings that can't be zeroed in memory, uncleared terminal output buffers, and force-unwraps in the app initializer.

The architecture is production-quality. The security layer needs targeted fixes before shipping.

---

## 1. Architecture & Code Structure

### 1.1 Project Layout

```
App/
├── Core/                          # Business logic, no UI dependencies
│   ├── Crypto/                    # Key management, Secure Enclave, Keychain
│   ├── SSH/                       # Session management, Citadel integration
│   └── Storage/                   # Actor-based persistence (JSON, Keychain)
├── Features/                      # Feature modules (view + logic)
│   ├── Connection/                # Profile CRUD, connection testing
│   ├── Terminal/                  # Terminal emulator, keyboard, voice input
│   ├── HostVerification/          # TOFU host key verification UI
│   ├── KeyManager/                # SSH key management UI
│   └── Settings/                  # Appearance, toolbar, notifications
├── UI/                            # Reusable UI components
├── Resources/                     # Fonts (FiraCode, JetBrainsMono, SourceCodePro)
├── ContentView.swift              # Root navigation
└── DivineMarsshApp.swift          # @main entry, dependency wiring
```

**Verdict:** Clean layering. Core has zero UI imports. Features are self-contained modules. Good separation between what could be a library (`Core/`) and what's app-specific (`Features/`).

### 1.2 Concurrency Model

The project uses Swift 6 strict concurrency throughout (`SWIFT_STRICT_CONCURRENCY: complete`).

| Pattern | Where Used | Purpose |
|---------|-----------|---------|
| `actor` | All stores (ProfileStore, KnownHostsStore, AppearanceStore, TerminalStateCache, KeyManager, SSHSession, HostKeyVerifier) | Thread-safe isolated state |
| `@MainActor` | All ViewModels, SSHSessionManager, SSHTerminalDataSource, TerminalViewController | UI-bound state and rendering |
| `AsyncStream` | SSHSession (connectionStateStream), shell output, scene phase observation | One-to-many state broadcasting |
| `Task` management | Keepalive, output feed, resize debounce, flush batching, scene phase | Structured background work with cancellation |
| `Sendable` | All models, enums, configs | Safe cross-actor boundary passing |

**Strengths:**
- No manual locks anywhere — actor isolation handles all synchronization
- All `Task` instances are cancelled in cleanup paths (`disconnect()`, `deinit`, `stopOutputFeed()`)
- `AsyncStream.Continuation.onTermination` used properly to prevent continuation leaks in `connectionStateStream()`

**Concerns:**
- `@unchecked Sendable` on `CitadelConnectionHandler`, `CitadelClientWrapper`, `WriterBox` — these bypass the compiler's concurrency safety checks. The types appear safe in practice (immutable fields or actor-protected access), but `@unchecked` silences real warnings if the code changes later. `WriterBox` in particular has a mutable `var writer` with no synchronization — it's only safe because of the usage pattern (set once before read), but the compiler can't verify this.

### 1.3 Data Flow: SSH to Terminal

```
User taps profile
  → ContentView.onChange(showTerminal)
    → SSHSessionManager.startSession(profile)
      → SSHSession.connect(profile)
        → CitadelConnectionHandler.connect()
          → resolveAuthMethod() [SE key / imported key / password from Keychain]
          → makeHostKeyValidator() → HostKeyVerifier (TOFU)
          → SSHClient.connect() [Citadel/NIO-SSH, 10s timeout]
          → returns CitadelClientWrapper
        → startKeepalive(interval)
      → state = .active

Terminal display:
  SSHSession.openShellChannel()
    → CitadelClientWrapper.openShell(pty, onOutput, onEnd)
      → AsyncStream<ShellOutput> [stdout | stderr]
        → SSHTerminalDataSource.handleOutput()
          → outputBuffer.append(bytes)
          → scheduleFlush() [16ms debounce]
            → terminalView.feed(byteArray:) [SwiftTerm renders]

User input:
  TerminalView keystroke
    → SSHTerminalDataSource.send(data:)
      → SSHSession.write(Data)
        → CitadelShellHandle.write(ByteBuffer)
          → remote shell
```

**Strengths:**
- Output buffering with 16ms flush prevents excessive SwiftTerm parsing on burst data
- Resize debouncing (100ms) prevents SSH window-change spam during rotation
- Clean separation: SSHTerminalDataSource owns the bridge between SSH I/O and terminal rendering

### 1.4 Dependency Injection & Testability

All external dependencies are abstracted behind protocols:

| Protocol | Production Implementation | Purpose |
|----------|--------------------------|---------|
| `SSHConnectionHandling` | `CitadelConnectionHandler` | SSH client connection |
| `SSHClientWrapping` | `CitadelClientWrapper` | SSH client operations |
| `SSHShellHandle` | `CitadelShellHandle` | PTY shell I/O |
| `ScenePhaseProviding` | `DefaultScenePhaseProvider` | App lifecycle observation |
| `NetworkPathProviding` | `DefaultNetworkPathProvider` | Network status checks |
| `BackgroundTaskProviding` | `DefaultBackgroundTaskProvider` | Background task API |

`SSHSessionManager` accepts a `connectionHandlerFactory` closure, making the entire SSH stack replaceable in tests. `SSHSession` accepts any `SSHConnectionHandling` implementation.

**Verdict:** Excellent testability design. Every external boundary is mockable.

### 1.5 State Management

The app follows a consistent **Model -> Actor Store -> ViewModel -> View** pattern:

```
TerminalAppearance (Codable struct)
  → AppearanceStore (actor, persists to appearance.json)
    → AppearanceViewModel (@MainActor, @Published)
      → SettingsView (SwiftUI)
        → TerminalViewRepresentable.updateUIViewController()
          → TerminalViewController.applyAppearance()
```

```
SSHConnectionProfile (Codable struct)
  → ProfileStore (actor, persists to profiles.json + Keychain)
    → ConnectionViewModel (@MainActor, @Published)
      → ConnectionListView / ConnectionEditorView
```

**Strengths:**
- `TerminalAppearance` uses `decodeIfPresent` for all properties in its custom `init(from:)` — new settings can be added without breaking existing user data
- ViewModels are thin bridges: load from actor, expose via @Published, forward mutations back to actor
- `AppearanceViewModel.binding(\.keyPath)` helper avoids boilerplate for two-way bindings

### 1.6 Persistence Layer

| Data | Format | Location | Backup Excluded |
|------|--------|----------|----------------|
| Connection profiles | JSON | `{appSupport}/DivineMarssh/profiles.json` | Yes |
| Passwords | Keychain | Service: `com.divinemarssh.passwords` | N/A (Keychain) |
| SSH keys (SE metadata) | JSON | `{appSupport}/DivineMarssh/se-keys.json` | Yes |
| SSH keys (imported) | Keychain + JSON metadata | Service: `com.divinemarssh.imported-keys` | Yes (metadata) |
| Known hosts | JSON | `{appSupport}/DivineMarssh/known_hosts.json` | Yes |
| Appearance settings | JSON | `{appSupport}/DivineMarssh/appearance.json` | No |
| Terminal state cache | JSON | `{caches}/DivineMarssh/terminal_state.json` | N/A (Caches) |

All JSON writes use `.atomic` option. Sensitive files are marked with `isExcludedFromBackup`.

**Concern:** Appearance settings are *not* excluded from backup. This is correct behavior (non-sensitive), but worth noting for completeness.

### 1.7 Third-Party Dependencies

| Dependency | Version | Role | Risk Assessment |
|-----------|---------|------|-----------------|
| **Citadel** | 0.9.0+ | SSH client (wraps NIO-SSH) | Medium — core security dependency, open-source, active maintenance |
| **SwiftNIO + NIO-SSH** | via Citadel | Async networking + SSH protocol | Low — Apple-maintained |
| **swift-crypto** | 3.15.1 | Crypto primitives | Low — Apple-maintained, wraps CryptoKit |
| **SwiftTerm** | 1.2.0+ | Terminal emulator UI (VT100) | Low — rendering only, no network access |
| **WhisperKit** | 0.16.0+ | On-device speech-to-text | Medium — ML model, large binary, runs locally (no cloud) |

WhisperKit is the heaviest dependency by far (ML models, swift-transformers, yyjson). It runs entirely on-device — no data leaves the app. Consider making it an optional download to reduce initial app size.

### 1.8 Test Coverage

```
Tests/
├── ConnectionTests/           ConnectionViewModel validation
├── CryptoTests/               KeyManager, KeychainKeyManager, SecureEnclaveKeyManager
├── HostVerificationTests/     FingerprintFormatter, FingerprintURIParser, KnownHostsStore
├── IntegrationTests/          Real SSH via Docker (port 2222), reconnection, host keys
├── SecurityTests/             AlgorithmPolicy, MemoryHygiene
├── SSHTests/                  SSHSession, SSHSessionManager lifecycle
├── StorageTests/              ProfileStore, TerminalStateCache, model serialization
├── TerminalTests/             SSHTerminalDataSource, KeyboardAccessory
└── CoverageBoostTests.swift   Supplementary edge cases
```

**Strengths:**
- Integration tests use a real Docker SSH server — not just mocks
- SSHSessionManager tests cover background/foreground transitions with mock providers
- Security-specific test suite for algorithm policy and memory hygiene

**Gaps:**
- No UI tests (XCUITest) for connection flow or terminal interaction
- HostKeyVerifier.verify() not directly tested with mismatch scenarios in unit tests (only in integration tests)
- No test for the `approvalHandler` wiring in DivineMarsshApp

---

## 2. Security Findings

### CRITICAL

#### S-01: Host Key Verification Bypassed in Production

**Location:** `App/DivineMarsshApp.swift:21`

```swift
let hostKeyVerifier = HostKeyVerifier(
    store: knownHostsStore,
    approvalHandler: { _ in true }  // Always approves
)
```

**Impact:** The TOFU (Trust On First Use) model is completely defeated. Every new server key is automatically trusted and stored without user confirmation. An attacker performing a MITM attack will have their key silently accepted and persisted. The `HostVerificationSheet` UI exists but is never triggered.

**Note:** The `HostKeyVerifier` actor itself is well-implemented — it correctly handles lookup, mismatch detection, and fingerprint comparison. The problem is purely in the wiring: the approval handler always returns `true`.

For known hosts that are already stored, mismatch detection *does* work — `verify()` throws `HostKeyVerificationError.mismatch` if the stored key differs. So subsequent connections to a previously-seen host are protected against key changes. But the first connection to any host is unprotected.

**Recommendation:** Wire the `approvalHandler` to present `HostVerificationSheet` and await user confirmation. The UI components already exist in `App/Features/HostVerification/`.

---

### HIGH

#### S-02: Passwords Returned as Immutable String

**Location:** `App/Core/Storage/ProfileStore.swift:80-81`

```swift
func password(for profileID: UUID) -> String? {
    loadPassword(for: profileID)
}
```

Swift `String` is a value type with copy-on-write semantics. Once a password is returned as `String`, the caller cannot securely erase it — `String` has no `withUnsafeMutableBytes` equivalent. The password may persist in memory across multiple ARC-managed copies.

`MemoryHygiene.zeroOut()` works for `[UInt8]` and `Data`, but is never applied to password strings.

**Recommendation:** Return passwords as `Data` or `[UInt8]` and use `MemoryHygiene.zeroOut()` in a `defer` block at the call site. Alternatively, use `ContiguousArray<UInt8>` as a password container.

---

#### S-03: Terminal Output Buffer Never Zeroed

**Location:** `App/Features/Terminal/SSHTerminalDataSource.swift:30, 187-194, 197-207`

```swift
private var outputBuffer: [UInt8] = []

private func handleOutput(_ output: ShellOutput) {
    // ...
    outputBuffer.append(contentsOf: bytes)
    scheduleFlush()
}

private func scheduleFlush() {
    // ...
    self.outputBuffer.removeAll(keepingCapacity: true)  // Data still in allocated memory
    // ...
}
```

`removeAll(keepingCapacity: true)` sets the count to zero but leaves the data in the allocated buffer. Sensitive command output (credentials echoed in terminals, private data) persists in the process address space.

**Recommendation:** Call `MemoryHygiene.zeroOut(&outputBuffer)` before clearing, or use `removeAll(keepingCapacity: false)` and accept the reallocation cost.

---

#### S-04: Force-Unwraps in App Initializer

**Location:** `App/DivineMarsshApp.swift:11-18`

```swift
let store = try! ProfileStore()
// ...
let kcManager = try! KeychainKeyManager()
let knownHostsStore = try! KnownHostsStore()
// ...
let terminalStateCache = try! TerminalStateCache()
```

Four `try!` calls in the `@main` struct initializer. If the Application Support directory is unavailable, restricted by MDM, or the Keychain is locked at launch, the app crashes instantly with no error message to the user.

**Recommendation:** Use `do/catch` with a fatal error screen, or use `try?` with a degraded-mode fallback. At minimum, wrap in a `do` block that logs the specific failure before crashing.

---

#### S-05: Clipboard Data Never Expires

**Location:** `App/Features/Terminal/SSHTerminalDataSource.swift:133-139`

```swift
nonisolated func clipboardCopy(source: TerminalView, content: Data) {
    Task { @MainActor in
        if let text = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = text
        }
    }
}
```

Data copied to the system clipboard persists indefinitely. Other apps can read it. If the user copies a password or sensitive output, it remains available to any app until manually overwritten.

**Recommendation:** Set `UIPasteboard.general.setItems(items, options: [.expirationDate: Date().addingTimeInterval(60)])` to auto-expire after 60 seconds. Or use `UIPasteboard.general.setItems(items, options: [.localOnly: true])` to prevent Handoff sharing.

---

### MEDIUM

#### S-06: Optional Biometric Protection for Passwords

**Location:** `App/Core/Storage/ProfileStore.swift:8, 97-108`

```swift
private let useBiometricProtection: Bool  // Defaults to true, but configurable

init(
    directory: URL? = nil,
    biometricPolicy: BiometricPolicy = BiometricPolicy(),
    useBiometricProtection: Bool = true  // Can be set to false
) throws {
```

While the default is `true`, the parameter allows disabling biometric protection. This is useful for testing, but there's no compile-time guard (`#if DEBUG`) preventing production code from passing `false`.

**Recommendation:** Add `#if DEBUG` around the `useBiometricProtection` parameter, or make it a private constant in production builds.

---

#### S-07: Empty Password Fallback

**Location:** `App/Core/SSH/SSHSession.swift:257`

```swift
case .password:
    let password = await profileStore.password(for: profile.id) ?? ""
    return .passwordBased(username: profile.username, password: password)
```

If the Keychain lookup fails (biometric denied, Keychain locked, data corrupted), the code silently falls back to an empty-string password and attempts authentication. This sends an auth attempt with no password instead of failing with a clear error.

**Recommendation:** Throw an explicit error when the password can't be retrieved:
```swift
guard let password = await profileStore.password(for: profile.id) else {
    throw SSHSessionError.authenticationFailed
}
```

---

#### S-08: `@unchecked Sendable` Usage

**Locations:**
- `App/Core/SSH/SSHSession.swift:216` — `CitadelConnectionHandler`
- `App/Core/SSH/SSHSession.swift:486` — `CitadelClientWrapper`
- `App/Core/SSH/SSHSession.swift:482` — `WriterBox`

These types opt out of the compiler's Sendable checks. `CitadelConnectionHandler` has only `let` properties (safe). `CitadelClientWrapper` wraps a single `let client` (safe). `WriterBox` has a mutable `var writer: TTYStdinWriter?` that is set once during `openShell()` and then only read — safe by convention but not by proof.

**Recommendation:** For `WriterBox`, consider using `OSAllocatedUnfairLock` or making the writer a `let` with a continuation-based initialization pattern.

---

#### S-09: No Connection Rate Limiting

**Impact:** There is no throttling on failed SSH connection or authentication attempts. An automated process could brute-force passwords at full speed against a target server.

**Recommendation:** Implement per-host exponential backoff after consecutive failures (e.g., 1s, 2s, 4s, 8s, capped at 30s).

---

#### S-10: Inconsistent RSA Policy

**Location:** `App/Core/SSH/AlgorithmPolicy.swift:48-51` vs `App/Core/Crypto/KeychainKeyManager.swift`

RSA is rejected for server host keys (`rejectedHostKeyTypes: ["ssh-rsa"]`) but accepted for client authentication keys. Users can import and use RSA private keys. This inconsistency sends a mixed signal about the app's security posture.

**Recommendation:** Either deprecate RSA client keys with a migration warning, or document the rationale (server keys must be modern, but users may need legacy client keys for older servers).

---

### LOW

#### S-11: No Idle Session Timeout

SSH sessions remain open indefinitely. If the user leaves the app in the foreground with an active connection, it stays connected forever (subject to server-side timeouts and keepalive). No local idle-timeout mechanism exists.

---

#### S-12: Default File Permissions on Created Directories

**Location:** `App/Core/Storage/ProfileStore.swift:21`

```swift
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
```

`createDirectory` uses default POSIX permissions (typically 755). On iOS this is mitigated by the app sandbox (other apps can't access), but explicit 700 permissions would be a defense-in-depth measure.

---

#### S-13: No Key Rotation or Age Warnings

No mechanism to track key age or suggest rotation. Long-lived SSH keys accumulate risk. A "key created N months ago — consider rotating" notice would improve security hygiene.

---

#### S-14: OpenSSH Key Comments Not Sanitized

Key comments from imported PEM files are displayed in the UI without length truncation or character sanitization. Extremely long or malformed comments could break layout.

---

## 3. Architecture Strengths

1. **Swift 6 strict concurrency everywhere.** No data races possible in well-typed code. Actors for all shared state, `@MainActor` for all UI. This is ahead of most iOS projects.

2. **Protocol-based DI across every external boundary.** SSH, networking, background tasks, scene phase — all mockable. Tests can verify complex lifecycle scenarios (background → foreground reconnection) without real infrastructure.

3. **Clean layering.** `Core/` has zero UIKit/SwiftUI imports. Could be extracted as an independent SSH library. `Features/` are self-contained verticals.

4. **MemoryHygiene utility.** The volatile-equivalent `memset_wrapper` with function pointer indirection is a well-implemented defense against dead-store elimination. Sensitive logging is disabled by default.

5. **AlgorithmPolicy is deny-by-default.** Uses NIO-SSH's built-in modern defaults (AES-GCM only) rather than Citadel's `.all` preset. Explicitly documents Terrapin mitigation. Validation methods exist for each algorithm category.

6. **Backward-compatible persistence.** `TerminalAppearance.init(from:)` uses `decodeIfPresent` for every property — new settings can be added without migration code.

7. **Integration tests with real SSH.** Docker-based SSH server for end-to-end testing. Not just mocked unit tests.

---

## 4. Architecture Concerns

1. **DivineMarsshApp.init() is a single point of failure.** All dependency construction and wiring happens in one `init()` with four `try!` calls. No error recovery, no staged initialization. A single Keychain hiccup crashes the app.

2. **SSHSessionManager is @MainActor but manages network-heavy operations.** While the actual SSH work happens on NIO event loops, the manager itself holds `@Published` properties and performs `await` calls on the main actor. This is correct for SwiftUI observation but means reconnection logic blocks the main actor's queue (though not the main thread, since it `await`s).

3. **No central error presentation.** Errors are caught in various places (ViewModels, data source, content view) but there's no unified error display mechanism. Some errors are shown as alerts, some as colored terminal text, some are silently swallowed (`try?`).

4. **Terminal state cache stores minimal data.** `CachedTerminalState` saves PTY config and basic metadata but not actual terminal scrollback content. After a background kill, the user reconnects to a blank terminal. This is a UX concern, not a bug — storing full scrollback would be complex and raise its own security questions.

5. **No navigation routing layer.** Navigation is driven by `@State` booleans in ContentView (`showTerminal`, `selectedProfile`). This works for the current simple flow but would become unwieldy with more screens.

---

## 5. Recommendations (Prioritized)

### Must Fix Before Release

| # | Finding | Effort |
|---|---------|--------|
| S-01 | Wire `approvalHandler` to present `HostVerificationSheet` and block until user approves/rejects | Medium — UI exists, needs async bridge |
| S-07 | Fail explicitly when password retrieval returns nil instead of falling back to empty string | Trivial |
| S-04 | Replace `try!` with `do/catch` and error UI or at least a descriptive `fatalError` message | Low |

### Should Fix

| # | Finding | Effort |
|---|---------|--------|
| S-05 | Add clipboard expiration (60s) via `UIPasteboard.setItems(_:options:)` | Trivial |
| S-03 | Zero terminal output buffer before clearing | Trivial |
| S-02 | Return passwords as `Data` instead of `String` for secure erasure | Low — API change propagates to a few call sites |
| S-06 | Guard `useBiometricProtection: false` behind `#if DEBUG` | Trivial |

### Nice to Have

| # | Finding | Effort |
|---|---------|--------|
| S-09 | Per-host connection rate limiting | Low-Medium |
| S-08 | Replace `WriterBox` with lock-based or continuation-based pattern | Low |
| S-10 | RSA deprecation warning in key import UI | Low |
| S-11 | Configurable idle session timeout | Medium |

---

## 6. Summary

The codebase is well-engineered. The concurrency model is exemplary for a Swift 6 project. Security fundamentals (Secure Enclave, algorithm policy, Keychain, TOFU infrastructure) are solid. The critical gap is that the TOFU verification UI is never actually triggered — fixing the `approvalHandler` wiring in `DivineMarsshApp.swift` would immediately close the most important vulnerability. The remaining findings are incremental hardening.
