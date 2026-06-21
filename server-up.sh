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
    PUBLIC_IPV4=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
    PUBLIC_IPV6=$(curl -6 -s ifconfig.me || curl -6 -s icanhazip.com || echo "")
    
    echo "--------------------------------------------------------"
    echo "✅ Success! Minecraft Server is now running in the background."
    echo ""
    
    if [ -n "$PUBLIC_IPV4" ]; then
        echo "🎮 Connect Address (IPv4): $PUBLIC_IPV4:25565"
    fi
    
    if [ -n "$PUBLIC_IPV6" ]; then
        echo "🎮 Connect Address (IPv6): [$PUBLIC_IPV6]:25565"
    fi
    
    if [ -z "$PUBLIC_IPV4" ] && [ -z "$PUBLIC_IPV6" ]; then
        echo "🎮 Connect Address: UNKNOWN_IP:25565"
    fi
    echo "--------------------------------------------------------"
    echo "To view live server logs, run:"
    echo "  sudo journalctl -u minecraft -f"
else
    echo "❌ Server failed to start! Check logs:"
    echo "  sudo journalctl -u minecraft -e"
fi
