# DivineMarssh

A security-focused iOS SSH terminal app built with Swift 6 and SwiftUI.

## Features

- Hardware-bound SSH keys via Secure Enclave (P-256 ECDSA)
- Imported key support (Ed25519, RSA-4096, ECDSA) with biometric gating
- Terminal emulation via SwiftTerm (VT100/xterm-256color)
- Trust-on-first-use (TOFU) host key verification with SHA256 fingerprints
- QR code scanning for pre-trusting host fingerprints
- Custom keyboard accessory bar (Esc, Tab, Ctrl lock, arrows, pipe, tilde, slash)
- Background/foreground session lifecycle with auto-reconnect
- Terminal state persistence and app state restoration
- Modern-only SSH algorithms (AES-GCM, ECDH, no legacy ciphers)
- Memory hygiene for sensitive data (passphrase zeroing, screenshot protection)

## Requirements

- iOS 17.0+
- Xcode 16.3+
- Swift 6.0

## Dependencies

All dependencies are managed via SPM:

| Package | Purpose |
|---------|---------|
| [Citadel](https://github.com/orlandos-nl/Citadel) | High-level SSH client API |
| [SwiftNIO SSH](https://github.com/Joannis/swift-nio-ssh) | SSH-2 protocol core (Citadel-compatible fork) |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator |
| [NIOTransportServices](https://github.com/apple/swift-nio-transport-services) | Network.framework integration |

## Build

```bash
# Open in Xcode
open DivineMarssh.xcodeproj

# Or build from command line
xcodebuild build \
  -project DivineMarssh.xcodeproj \
  -scheme DivineMarssh \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Run Tests

```bash
xcodebuild test \
  -project DivineMarssh.xcodeproj \
  -scheme DivineMarssh \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Some tests (Secure Enclave key operations, biometric prompts) require a physical device.

### Integration Tests

A Docker-based SSH test server is provided for integration testing:

```bash
docker compose up -d
# Run tests targeting the local SSH server on port 2222
```

## Project Structure

```
App/
  DivineMarsshApp.swift          # App entry point
  ContentView.swift              # Root navigation
  Core/
    SSH/                         # SSH session, connection state, algorithm policy
    Crypto/                      # Key managers (Secure Enclave, Keychain), memory hygiene
    Storage/                     # Profile store, known hosts, terminal state cache
  Features/
    Connection/                  # Connection list and editor views
    Terminal/                    # Terminal view, keyboard accessory, data source
    KeyManager/                  # Key management views
    HostVerification/            # Host key verification, QR fingerprint scanner
  UI/
    Components/                  # Shared UI components
Tests/
  DivineMarsshTests/             # Unit, integration, and coverage tests
```

## Architecture

- Swift 6 strict concurrency throughout (actors, Sendable types)
- SwiftUI lifecycle with UIViewControllerRepresentable bridge for SwiftTerm
- Actor-based stores (ProfileStore, KnownHostsStore, TerminalStateCache)
- Protocol-based dependency injection for testability
- Passwords stored in iOS Keychain (never in profile JSON)
- Known hosts excluded from iCloud backup

## Usage

1. Launch the app and tap + to add a new connection
2. Enter host, port, username, and select an authentication method:
   - Generate a Secure Enclave key (most secure, hardware-bound)
   - Import an existing PEM key (Ed25519, RSA, ECDSA)
   - Use password authentication
3. For SE/imported keys, copy the public key from Key Manager and add it to your server's `authorized_keys`
4. Connect. On first connection, verify the host fingerprint displayed matches your server
5. Use the keyboard accessory bar for special keys (Esc, Tab, Ctrl, arrows)

## License

Private project.
