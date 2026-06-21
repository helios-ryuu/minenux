#!/usr/bin/env bash

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "Starting Minecraft Server Daemon..."
systemctl start minecraft

# Wait briefly
sleep 2

if systemctl is-active --quiet minecraft; then
    echo "--------------------------------------------------------"
    echo "✅ Success! Minecraft Server is now running in the background."
    echo ""
    
    # Execute ip.sh to list all available interfaces
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$DIR/ip.sh" ]; then
        bash "$DIR/ip.sh"
    fi
    
    echo "--------------------------------------------------------"
    echo "To view live server logs, run:"
    echo "  sudo journalctl -u minecraft -f"
else
    echo "❌ Server failed to start! Check logs:"
    echo "  sudo journalctl -u minecraft -e"
fi
