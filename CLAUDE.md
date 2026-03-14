# DivineMarssh - Project Notes

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
