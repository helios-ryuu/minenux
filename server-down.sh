#!/usr/bin/env bash

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "Stopping Minecraft Server..."
systemctl stop minecraft

if ! systemctl is-active --quiet minecraft; then
    echo "🛑 Server successfully stopped."
else
    echo "⚠️ Warning: The server process may still be stopping or hanging. Check with:"
    echo "  sudo systemctl status minecraft"
fi
