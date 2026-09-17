#!/bin/bash
set -euo pipefail

REPO="akshayram1/ChatVault"
TMP_DMG="$(mktemp -t ChatVault).dmg"
MOUNT_POINT="/tmp/ChatVault-mount-$$"

echo "Downloading ChatVault..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/ChatVault.dmg" -o "$TMP_DMG"

echo "Mounting..."
mkdir -p "$MOUNT_POINT"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

echo "Installing to ~/Applications..."
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ChatVault.app"
cp -R "$MOUNT_POINT/ChatVault.app" "$HOME/Applications/ChatVault.app"

echo "Cleaning up..."
hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT" 2>/dev/null || true
rm -f "$TMP_DMG"

echo "Launching ChatVault..."
open "$HOME/Applications/ChatVault.app"

echo "Done. Look for the chat bubble icon in the menu bar (top of the screen)."
