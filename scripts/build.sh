#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
VERSION=$(<VERSION)
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
APP="$PWD/dist/Archaive.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Archaive "$APP/Contents/MacOS/Archaive"
swift scripts/app-icon.swift .build/Archaive.iconset
iconutil -c icns .build/Archaive.iconset -o "$APP/Contents/Resources/Archaive.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Archaive</string>
<key>CFBundleIdentifier</key><string>local.archaive.app</string>
<key>CFBundleName</key><string>Archaive</string>
<key>CFBundleIconFile</key><string>Archaive</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Share your Mac screen with your phone on the same local network.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
