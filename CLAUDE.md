# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Branding
- The user-facing app name is **tunlr**. Never show "DivineMarssh" in UI — that is only the internal/Xcode project name.

## Build and Test

```bash
# Build
xcodebuild build -project DivineMarssh.xcodeproj -scheme DivineMarssh -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Test (all)
xcodebuild test -project DivineMarssh.xcodeproj -scheme DivineMarssh -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Test (single suite)
xcodebuild test -project DivineMarssh.xcodeproj -scheme DivineMarssh -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:DivineMarsshTests/ProfileStoreTests

# Integration test SSH server (Docker)
docker compose up -d    # start server on port 2222
docker compose down     # stop server
```

If `name=iPhone 16 Pro` is ambiguous (multiple iOS versions installed), use a specific simulator UUID from `xcrun simctl list devices available`.

**Never launch or boot the iOS Simulator.** The user tests in Xcode directly. Only use `xcodebuild build` and `xcodebuild test` for CLI verification.

## Critical Constraints

- **Never run `xcodegen generate`** — it resets App Store configuration in pbxproj and Info.plist. The `project.yml` is a reference, not the source of truth.
- New source files must be manually added to `project.pbxproj` in 4 places: PBXFileReference, PBXGroup children, PBXBuildFile, PBXSourcesBuildPhase.
- Passwords go in Keychain, never in profile JSON.

## Key Patterns

- Swift 6 strict concurrency: all stores are actors, models are Sendable
- Tests use both Swift Testing (`@Test`, `#expect`) and XCTest (`XCTestCase`); prefer Swift Testing for new tests
- UI views use `@MainActor` isolation
- Dependency injection via protocols for testability (SSHClientProtocol, ConnectionHandlerProtocol, etc.)
- Known hosts file excluded from iCloud backup

## Architecture: Settings & Appearance

Settings follow a consistent pattern: **Model → Actor Store → ViewModel → View → Terminal**.

1. `TerminalAppearance` (Codable, Sendable struct) — all terminal settings (font, theme, cursor, scrollback, toolbar buttons, shortcut packs). Uses custom `init(from:)` with `decodeIfPresent` for backward-compatible JSON decoding.
2. `AppearanceStore` (actor) — persists to `appearance.json` in Application Support
3. `AppearanceViewModel` (@MainActor, ObservableObject) — bridges actor ↔ SwiftUI
4. Settings views use `binding(\.keyPath)` helper for generic property bindings
5. `TerminalViewRepresentable.updateUIViewController()` calls `TerminalViewController.applyAppearance()` to apply settings to SwiftTerm

To add a new setting: add property with default to `TerminalAppearance` + add `decodeIfPresent` line in `init(from:)` + add UI in settings view + apply in `applyAppearance()`.

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

### Authentication Methods
- **Secure Enclave key**: P-256 ECDSA via `SecureEnclaveP256SSHKey`, biometric-protected
- **Imported key**: Ed25519/P-256 from files, stored in Keychain
- **Password**: stored in Keychain with biometric protection

## Architecture: Terminal UI

- `SimpleTerminalAccessory` (UIInputView) — data-driven keyboard toolbar, configured by `[ToolbarButtonKind]` array from appearance settings. Mic and hide-keyboard buttons are always appended.
- `ShortcutPacksSheetView` — tabbed shortcuts sheet with predefined packs (Shell, Tmux, Vim, Claude). Packs defined in `ShortcutPackCatalog`. Users enable/disable packs and can favorite individual shortcuts.
- Voice input via on-device WhisperKit speech-to-text (not cloud-based).
