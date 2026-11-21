# Archaive for iPhone

A native SwiftUI companion for Archaive on Mac. Requires iOS 17 or later, Xcode 16 or later, and a Mac running Archaive’s phone-sharing feature. No third-party dependencies or cloud service.

## Install on your iPhone

1. Open `iOS/ArchaivePhone.xcodeproj` in Xcode and select the **ArchaivePhone** scheme.
2. Under **Signing & Capabilities**, choose your own Apple development team. Change `local.archaive.phone` to a unique bundle identifier if your signing account requires it.
3. Connect your iPhone, enable Developer Mode if requested, choose it as the run destination, and press Run. Follow any developer trust prompts on the phone.

An Apple signing identity and provisioning profile are required to install on a physical iPhone. The repository does not include them. This companion is not yet available on the App Store or TestFlight. Personal Team installs may expire and require rebuilding.

## Pair, view, and control

On the Mac, open **Connections → Open Sharing**. To enable mouse and keyboard input, turn on **Allow remote control** and grant Archaive access under **System Settings → Privacy & Security → Accessibility** if prompted. Then choose **Start Sharing** and approve screen capture. Both devices need to be on the same Wi-Fi or phone hotspot.

On iPhone, tap **Scan QR Code** and scan the code in the Mac’s sharing window. Approve Camera and Local Network access when prompted. **Copy View Link** on the Mac gives you a link you can paste into the iPhone app or open in a browser for viewing. To pair for control, scan the control QR directly in Archaive. If you close the setup window, restart sharing to show a fresh control QR code.

- **View** lets you pinch to zoom and drag to pan. **Fit** resets the zoom.
- Tap the fullscreen button to hide the viewer toolbar. The current View or Control mode stays active. Tap the arrows in the top-right corner to exit fullscreen.
- **Control** lets you tap or double-tap to click, touch and hold to right-click, drag with one finger, and scroll with two. To zoom in on a small target, zoom in View first, then switch to Control.
- In Control, tap the keyboard button to send text and use Mac keys or shortcuts. The Mac applies keyboard input to the focused app.
- **Disconnect** leaves the viewer. **Stop Phone Sharing** on the Mac ends the session and revokes control. Backgrounding Archaive hides the image and pauses the connection. Locking the Mac ends the session.

The app keeps session links and frames in memory. The screen stream uses local HTTP, so anyone holding a view link can see it. Control QR codes carry a separate secret that authenticates the video in Control mode and encrypts keyboard and touch commands. Keep the code private and use a trusted local network.

Phone brightness stays under your control. Closed-lid use still requires keep awake and an active display exposed by macOS.

## Verify

From the repository root:

```sh
./scripts/test.sh
xcodebuild -project iOS/ArchaivePhone.xcodeproj -scheme ArchaivePhone \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/iphone CODE_SIGNING_ALLOWED=NO build
```

The shared standalone regression harness checks valid LAN/hotspot pairing links, malformed tokens, public endpoints, credentials, expired server routes, and control authentication and replay rejection. Simulator can exercise paste-link pairing and rendering against a local stream; physical camera scanning, local-network prompts on a real phone, and closed-lid/zero-brightness capture require device testing.

To regenerate the matching white **A** app icon:

```sh
swift scripts/phone-icon.swift iOS/ArchaivePhone/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```
