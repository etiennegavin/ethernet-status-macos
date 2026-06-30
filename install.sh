#!/bin/bash
set -e

APP_NAME="EthernetStatus"
BUNDLE_ID="com.user.ethernetstatus"
APP_DEST="/Applications/$APP_NAME.app"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/$BUNDLE_ID.plist"

# ── 1. Build ──────────────────────────────────────────────
echo "▶ Baue $APP_NAME..."
swift build -c release 2>&1 | grep -v "^Build complete"

rm -rf "EthernetStatus.app"
mkdir -p "EthernetStatus.app/Contents/MacOS"
cp ".build/release/$APP_NAME" "EthernetStatus.app/Contents/MacOS/"

cat > "EthernetStatus.app/Contents/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>EthernetStatus</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.ethernetstatus</string>
    <key>CFBundleName</key>
    <string>EthernetStatus</string>
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
PLIST_EOF

codesign --force --sign - "EthernetStatus.app"
echo "  ✓ Build fertig"

# ── 2. Nach /Applications installieren ───────────────────
echo "▶ Installiere nach /Applications..."
rm -rf "$APP_DEST"
cp -r "EthernetStatus.app" "$APP_DEST"
echo "  ✓ /Applications/EthernetStatus.app"

# ── 3. LaunchAgent erstellen ──────────────────────────────
echo "▶ Richte LaunchAgent ein..."
mkdir -p "$LAUNCH_AGENTS"

cat > "$PLIST" << AGENT_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.ethernetstatus</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/EthernetStatus.app/Contents/MacOS/EthernetStatus</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/ethernetstatus.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ethernetstatus.err</string>
</dict>
</plist>
AGENT_EOF

# ── 4. Laufende Instanz beenden und LaunchAgent laden ─────
echo "▶ Starte neu..."
pkill -x EthernetStatus 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
sleep 0.5
launchctl load "$PLIST"

echo ""
echo "✅ Fertig! EthernetStatus läuft jetzt:"
echo "   • Startet automatisch beim Login"
echo "   • Startet automatisch neu bei Absturz"
echo ""
echo "   Deinstallieren: launchctl unload $PLIST && rm $PLIST"
