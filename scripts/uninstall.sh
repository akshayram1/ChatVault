#!/bin/bash
set -euo pipefail

echo "Quitting ChatVault..."
killall ChatSessions 2>/dev/null || true

echo "Removing app..."
rm -rf "$HOME/Applications/ChatSessions.app"
rm -rf "/Applications/ChatSessions.app"

echo "Removing saved preferences..."
defaults delete com.chatsessions.app 2>/dev/null || true

echo "Done. ChatVault has been uninstalled."
