#!/bin/zsh
# Builds, installs to ~/Applications and starts at login (LaunchAgent).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
DEST="$HOME/Applications/ClaudeUsageBar.app"
PLIST="$HOME/Library/LaunchAgents/com.talex-tnt.claude-usage-bar.plist"

pkill -x ClaudeUsageBar 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R build/ClaudeUsageBar.app "$DEST"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.talex-tnt.claude-usage-bar</string>
    <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/ClaudeUsageBar</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/com.talex-tnt.claude-usage-bar" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed to $DEST and started (login item via LaunchAgent)."
