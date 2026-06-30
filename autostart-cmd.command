#!/bin/bash
# EthernetStatus – Autostart einrichten
# Dieses Skript richtet den automatischen Start beim Login ein.
# Setup autostart on login / Configurer le démarrage automatique

APP="/Applications/EthernetStatus.app"
PLIST="$HOME/Library/LaunchAgents/com.user.ethernetstatus.plist"

# App prüfen / Check app / Vérifier l'app
if [ ! -d "$APP" ]; then
    osascript -e 'display dialog "EthernetStatus.app wurde nicht gefunden.\n\nBitte zuerst die App aus dem DMG in den Programme-Ordner ziehen, dann dieses Skript erneut ausführen.\n\n---\n\nEthernetStatus.app not found.\nPlease drag the app from the DMG to Applications first." buttons {"OK"} default button "OK" with icon stop with title "EthernetStatus – Autostart"'
    exit 1
fi

# LaunchAgent erstellen
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" << 'PLIST_EOF'
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
PLIST_EOF

# Laden / Load / Charger
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

osascript -e 'display dialog "✅ Autostart erfolgreich eingerichtet!\n\nEthernetStatus startet jetzt automatisch beim Login und neu nach einem Absturz.\n\n---\n\n✅ Autostart set up successfully!\n\nEthernetStatus will now start automatically at login and restart after crashes." buttons {"OK"} default button "OK" with icon note with title "EthernetStatus – Autostart"'
