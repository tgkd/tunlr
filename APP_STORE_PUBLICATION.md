# App Store Publication Guide — tunlr

## Current State

| Field | Value |
|---|---|
| Bundle ID | `com.tunlr.app` |
| Display Name | tunlr |
| Version | 0.0.1 |
| Build | 11 |
| Min iOS | 17.0 |
| Category | Developer Tools |
| Team ID | ULU867Y7LC |
| Encryption | Non-exempt (no compliance docs needed) |

---

## Pre-Submission Checklist

### 1. App Store Connect Setup

- [ ] Create app record in [App Store Connect](https://appstoreconnect.apple.com)
  - Bundle ID: `com.tunlr.app`
  - SKU: choose a unique identifier (e.g., `tunlr-ssh-001`)
  - Primary Language: English (U.S.)
  - Category: Developer Tools

### 2. Version & Build Number

- [ ] Update `MARKETING_VERSION` in pbxproj to `1.0.0` (or your chosen release version)
- [ ] Increment `CURRENT_PROJECT_VERSION` for each upload (currently `11`)

### 3. Signing & Provisioning

- [ ] Create **App Store Distribution** certificate in Apple Developer portal (if not already)
- [ ] Create **App Store** provisioning profile for `com.tunlr.app`
- [ ] In Xcode: set signing to "Automatically manage signing" or manually select the distribution profile

### 4. Privacy Descriptions — Fix Branding

Several privacy strings still say "DivineMarssh" instead of "tunlr". Fix before submission:

| Key | Current | Should Be |
|---|---|---|
| NSCameraUsageDescription | "DivineMarssh may use the camera..." | "tunlr uses the camera to scan QR codes for importing SSH keys." |
| NSFaceIDUsageDescription | "DivineMarssh uses Face ID..." | "tunlr uses Face ID to protect your SSH keys and authenticate securely." |
| NSLocalNetworkUsageDescription | "DivineMarssh needs local network access..." | "tunlr needs local network access to connect to SSH servers on your network." |

NSMicrophoneUsageDescription already says "tunlr" — no change needed.

### 5. Privacy Manifest (PrivacyInfo.xcprivacy)

Apple requires a privacy manifest for apps using certain APIs. Create `App/PrivacyInfo.xcprivacy` declaring:

- **NSPrivacyAccessedAPITypes**: List any required reason APIs used (e.g., UserDefaults, file timestamp, disk space)
- **NSPrivacyCollectedDataTypes**: Likely none (app processes everything on-device)
- **NSPrivacyTracking**: `false`
- **NSPrivacyTrackingDomains**: empty

WhisperKit and Citadel may bundle their own privacy manifests. Verify by checking their SPM packages.

### 6. App Icon

Already configured: `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024x1024). Xcode auto-generates all required sizes.

### 7. Screenshots

Required sizes (at minimum):

| Device | Size | Required |
|---|---|---|
| iPhone 6.9" (16 Pro Max) | 1320 x 2868 | Yes |
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | Yes (or use 6.9") |
| iPhone 6.5" (11 Pro Max) | 1284 x 2778 | Yes (or use 6.7") |
| iPad Pro 13" | 2064 x 2752 | Yes, if iPad supported |

- Min 3 screenshots, max 10 per device size
- See `app-store-screenshots-brief.md` for branding and feature priority

### 8. App Store Metadata

Prepare the following text:

#### App Name
`tunlr`

#### Subtitle (30 chars max)
`SSH Terminal for iOS` (20 chars)

#### Promotional Text (170 chars, editable without review)
Write a short pitch, e.g.:
> Secure SSH terminal with biometric-protected keys, on-device voice input, and customizable themes. Built for developers.

#### Description (4000 chars max)
Should cover:
- SSH terminal emulation (SwiftTerm-based, xterm-256color)
- Authentication: Secure Enclave keys (biometric), imported Ed25519/P-256 keys, Keychain passwords
- On-device voice input via WhisperKit (no cloud processing)
- Connection profiles with auto-reconnect
- 9 color themes, 4 monospace fonts, adjustable font size
- Host key verification (TOFU model + QR code scanning)
- Keyboard toolbar with shortcut packs (Shell, Tmux, Vim, Claude)
- iPad support with full landscape/portrait orientations
- No data collection, no analytics, no tracking

#### Keywords (100 chars max, comma-separated)
`ssh,terminal,remote,server,shell,developer,cli,console,secure,voice`

#### Support URL
Required. Set up a support page, GitHub repo, or landing page.

#### Privacy Policy URL
Required. Must describe data handling (the app collects no data and processes everything on-device).

#### Category
Primary: Developer Tools
Secondary: Utilities (optional)

### 9. Age Rating

Answer the questionnaire in App Store Connect. For tunlr:
- No objectionable content
- No web access (SSH only, no browser)
- No user-generated content sharing
- Expected rating: **4+**

### 10. App Review Notes

Provide context for the reviewer since SSH requires a server:

> tunlr is an SSH client. To test, you can connect to any SSH server. The app requires a remote server to demonstrate functionality — it is a terminal client, not a standalone tool. No login credentials are needed for the app itself; authentication is to the user's own SSH servers.

If you have a demo server, provide credentials. Otherwise, the above explanation is standard for SSH apps.

---

## Build & Upload

```bash
# 1. Archive
xcodebuild archive \
  -project DivineMarssh.xcodeproj \
  -scheme DivineMarssh \
  -destination 'generic/platform=iOS' \
  -archivePath build/tunlr.xcarchive

# 2. Export for App Store
xcodebuild -exportArchive \
  -archivePath build/tunlr.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist

# 3. Upload (or use Xcode Organizer → Distribute App)
xcrun altool --upload-app \
  -f build/export/DivineMarssh.ipa \
  -t ios \
  -u YOUR_APPLE_ID \
  -p @keychain:AC_PASSWORD
```

Alternative: Use **Xcode → Product → Archive → Distribute App** (simpler).

#### ExportOptions.plist (create if using CLI)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>ULU867Y7LC</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

---

## Common Rejection Reasons to Avoid

1. **Incomplete metadata** — Missing screenshots, privacy policy URL, or support URL
2. **Privacy description mismatch** — Requesting permissions the app doesn't visibly use. Camera (QR scanning) and Microphone (voice input) are both used, so these are fine
3. **Broken functionality** — App Store reviewers may not have an SSH server. Provide clear review notes
4. **Missing privacy manifest** — Apple increasingly enforces this; add PrivacyInfo.xcprivacy
5. **Third-party SDK privacy** — Ensure WhisperKit's required reason APIs are declared

---

## Open-Source Licenses

The About screen (`App/Features/Settings/AboutView.swift`) currently lists 5 libraries. Consider adding remaining transitive dependencies for full legal compliance. All use MIT or Apache 2.0 (both require attribution, which is satisfied by the in-app licenses screen).

---

## Launch Checklist (Day of Submission)

- [ ] Privacy descriptions use "tunlr" branding (not "DivineMarssh")
- [ ] Version set to release number (e.g., 1.0.0)
- [ ] Privacy manifest added
- [ ] Screenshots uploaded for all required device sizes
- [ ] App description, keywords, subtitle filled in
- [ ] Privacy policy URL live
- [ ] Support URL live
- [ ] Review notes written
- [ ] Archive built and uploaded
- [ ] TestFlight build tested on physical device
