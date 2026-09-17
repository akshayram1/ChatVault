#!/bin/bash
set -euo pipefail

echo "Quitting ChatVault..."
killall ChatVault 2>/dev/null || true
killall ChatSessions 2>/dev/null || true

echo "Removing app..."
rm -rf "$HOME/Applications/ChatVault.app"
rm -rf "/Applications/ChatVault.app"
# Builds before v1.0.3 shipped under the old name.
rm -rf "$HOME/Applications/ChatSessions.app"
rm -rf "/Applications/ChatSessions.app"

echo "Removing saved preferences..."
defaults delete com.chatvault.app 2>/dev/null || true
defaults delete com.chatsessions.app 2>/dev/null || true

echo "Done. ChatVault has been uninstalled."
