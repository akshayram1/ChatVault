#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SDK="$(xcrun --show-sdk-path)"
BIN_DIR="$ROOT/.build/release"
mkdir -p "$BIN_DIR"
swiftc -parse-as-library \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -lsqlite3 \
  -o "$BIN_DIR/ChatSessions" \
  Sources/ChatSessions/*.swift
APP="$ROOT/dist/ChatSessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ChatSessions" "$APP/Contents/MacOS/ChatSessions"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/ChatSessions"
if command -v codesign >/dev/null; then
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"
