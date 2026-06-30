#!/bin/bash
set -e

APP_NAME="EthernetStatus"
BUNDLE_ID="com.user.ethernetstatus"
APP_BUNDLE="$APP_NAME.app"

echo "Baue $APP_NAME ..."
swift build -c release

echo "Erstelle App-Bundle ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Ethernet Status</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

# Ad-hoc code sign (required to run without Gatekeeper complaints)
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "Fertig: $APP_BUNDLE"
echo ""
echo "Jetzt starten:"
echo "  open $APP_BUNDLE"
echo ""
echo "Nach /Applications installieren:"
echo "  cp -r $APP_BUNDLE /Applications/"
