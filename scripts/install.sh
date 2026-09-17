#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building ChatSessions..."
chmod +x scripts/build-app.sh
./scripts/build-app.sh

APP_SRC="$ROOT/dist/ChatSessions.app"
APP_DEST="$HOME/Applications/ChatSessions.app"

echo "Installing to ~/Applications..."
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

echo "Launching ChatSessions..."
open "$APP_DEST"

echo "Done. Look for the chat bubble icon in the menu bar (top of the screen)."
echo "Installed to: $APP_DEST"
