# Archaive for iPhone

A native SwiftUI companion for Archaive on Mac. Requires iOS 17 or later, Xcode 16 or later, and a Mac running Archaive’s phone-sharing feature. No third-party dependencies or cloud service.

## Install on your iPhone

1. Open `iOS/ArchaivePhone.xcodeproj` in Xcode and select the **ArchaivePhone** scheme.
2. Under **Signing & Capabilities**, choose your own Apple development team. Change `local.archaive.phone` to a unique bundle identifier if your signing account requires it.
3. Connect your iPhone, enable Developer Mode if requested, choose it as the run destination, and press Run. Follow any developer trust prompts on the phone.

An Apple signing identity and provisioning profile are required to install on a physical iPhone. The repository does not include them. This companion is not yet available on the App Store or TestFlight. Personal Team installs may expire and require rebuilding.

## Pair and view

On the Mac, choose **Share Screen to Phone… → Start Sharing** and approve screen capture. On iPhone, choose **Scan QR Code** and approve Camera and Local Network access. Scan the code in the Mac’s sharing window. **Paste the sharing link** provides a fallback when the camera is unavailable, including in Simulator. Both devices need a reachable private IPv4 address on the same Wi-Fi or phone hotspot; network device isolation can block connections.

Pinch to zoom, drag to pan, turn the phone for landscape, and tap **Fit** to reset zoom. **Disconnect** leaves the viewer; **Stop Phone Sharing** in the Mac menu ends the server. The app does not save session links, stream frames to disk, or send them to a cloud service. Backgrounding hides the image, pauses requests, and releases the idle-sleep override. Returning resumes a still-active session. A new sharing session requires scanning its fresh code.

The native renderer uses the Mac’s captured JPEG frames directly. Physical Mac dimming does not apply to those pixels, and iPhone brightness stays under your control. Sharing is view-only, without audio or remote input. Closed-lid use still requires keep awake and an active display exposed by macOS. It does not bypass screen locking or create a virtual display.

Sharing uses unencrypted local HTTP. Use a trusted network: anyone holding the session link can view the stream. The app accepts only Archaive-shaped session links with private/link-local IPv4 hosts, rejects credentials/query strings/fragments, and blocks HTTP redirects. Camera permission is requested only when you tap Scan.

## Verify

From the repository root:

```sh
./scripts/test.sh
xcodebuild -project iOS/ArchaivePhone.xcodeproj -scheme ArchaivePhone \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/iphone CODE_SIGNING_ALLOWED=NO build
```

The shared standalone regression harness checks valid LAN/hotspot pairing links, malformed tokens, public endpoints, credentials, and expired server routes. Simulator can exercise paste-link pairing and rendering against a local stream; physical camera scanning, local-network prompts on a real phone, and closed-lid/zero-brightness capture require device testing.

To regenerate the matching white **A** app icon:

```sh
swift scripts/phone-icon.swift iOS/ArchaivePhone/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```
