# DivineMarssh - Project Notes

## Branding
- The user-facing app name is **tunlr**. Never show "DivineMarssh" in UI — that is only the internal/Xcode project name.

## Build and Test

```bash
# Build
xcodebuild build -project DivineMarssh.xcodeproj -scheme DivineMarssh -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Test
xcodebuild test -project DivineMarssh.xcodeproj -scheme DivineMarssh -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Integration test SSH server (Docker)
docker compose up -d    # start server on port 2222
docker compose down     # stop server
```

## Key Patterns

- Swift 6 strict concurrency: all stores are actors, models are Sendable
- Tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- New source files must be added to `DivineMarssh.xcodeproj/project.pbxproj` (file reference, group, build phase)
- Passwords go in Keychain, never in profile JSON
- Known hosts file excluded from iCloud backup
- UI views use `@MainActor` isolation
- Dependency injection via protocols for testability (SSHClientProtocol, ConnectionHandlerProtocol, etc.)
- `project.yml` defines Xcode project structure (XcodeGen format); `.xcodeproj` can be regenerated from it

## Architecture: SSH Connections

### Connection Lifecycle
1. User taps profile → `SSHSessionManager.startSession(profile)` → creates `SSHSession` actor
2. `SSHSession.connect()` sets state to `.connecting`, delegates to `CitadelConnectionHandler`
3. `CitadelConnectionHandler` resolves auth, validates host key (TOFU), calls Citadel `SSHClient.connect()` (10s timeout)
4. On success: state → `.connected`, opens PTY (80×24, xterm-256color) + shell channel
5. `SSHTerminalDataSource` bridges SSH I/O ↔ SwiftTerm `TerminalView`
6. Disconnect: cancels shell, closes client, state → `.disconnected`

### Background/Foreground Handling (`SSHSessionManager`)
- Background: caches terminal state, gracefully disconnects SSH session
- Foreground: if `autoReconnect` enabled + network available → reconnects and restores PTY config

### Key Components
- `SSHSession` (actor, `App/Core/SSH/SSHSession.swift`): connection state machine + SSH operations
- `SSHSessionManager` (`App/Core/SSH/SSHSessionManager.swift`): app-level lifecycle, background/foreground
- `CitadelConnectionHandler` (in SSHSession.swift): Citadel SSH client integration
- `SSHTerminalDataSource` (`App/Features/Terminal/SSHTerminalDataSource.swift`): terminal ↔ SSH I/O bridge
- `ProfileStore` (actor, `App/Core/Storage/ProfileStore.swift`): persists profiles + Keychain passwords
- `HostKeyVerifier` (actor, `App/Features/HostVerification/HostKeyVerifier.swift`): TOFU host key verification
- `ConnectionViewModel` (`App/Features/Connection/ConnectionViewModel.swift`): CRUD for profiles

### Authentication Methods
- **Secure Enclave key**: P-256 ECDSA via `SecureEnclaveP256SSHKey`, biometric-protected
- **Imported key**: Ed25519/P-256 from files, stored in Keychain
- **Password**: stored in Keychain with biometric protection

### Connection List UI
- `lastConnected: Date?` on `SSHConnectionProfile` is set on successful connection
- Displayed as relative time via `Text(date, style: .relative)` (e.g. "1 min, 27 sec")
- List sorted by `lastConnected` (most recent first)
- Connection state indicator in terminal toolbar: green (connected), red (disconnected), spinner (connecting/reconnecting)
