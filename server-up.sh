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
    # Grab public IP using an external API
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "UNKNOWN_IP")
    echo "--------------------------------------------------------"
    echo "✅ Success! Minecraft Server is now running in the background."
    echo ""
    echo "🎮 Connect Address: $PUBLIC_IP:25565"
    echo "--------------------------------------------------------"
    echo "To view live server logs, run:"
    echo "  sudo journalctl -u minecraft -f"
else
    echo "❌ Server failed to start! Check logs:"
    echo "  sudo journalctl -u minecraft -e"
fi
