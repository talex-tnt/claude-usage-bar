#!/bin/zsh
# Builds ClaudeUsageBar.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ClaudeUsageBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos13 Sources/main.swift -o "$APP/Contents/MacOS/ClaudeUsageBar"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
