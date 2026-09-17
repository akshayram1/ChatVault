#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building ChatVault..."
chmod +x scripts/build-app.sh
./scripts/build-app.sh

APP_SRC="$ROOT/dist/ChatVault.app"
APP_DEST="$HOME/Applications/ChatVault.app"

echo "Installing to ~/Applications..."
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

echo "Launching ChatVault..."
open "$APP_DEST"

echo "Done. Look for the chat bubble icon in the menu bar (top of the screen)."
echo "Installed to: $APP_DEST"
