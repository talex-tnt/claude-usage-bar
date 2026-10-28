#!/bin/zsh
set -u
PLIST="$HOME/Library/LaunchAgents/com.talex-tnt.claude-usage-bar.plist"
launchctl bootout "gui/$(id -u)/com.talex-tnt.claude-usage-bar" 2>/dev/null
pkill -x ClaudeUsageBar 2>/dev/null
rm -f "$PLIST"
rm -rf "$HOME/Applications/ClaudeUsageBar.app"
echo "Uninstalled."
