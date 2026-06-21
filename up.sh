#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
require_root

echo "Starting Minecraft Server Daemon..."
systemctl start minecraft

# Wait briefly
sleep 2

if is_server_running; then
    echo "--------------------------------------------------------"
    echo "✅ Success! Minecraft Server is now running in the background."
    echo ""

    if [ -f "$DIR/ip.sh" ]; then
        bash "$DIR/ip.sh"
    fi

    CURRENT_MAP=$(prop_get level-name)
    apply_pending_gamerules "$CURRENT_MAP"

    echo "--------------------------------------------------------"
    echo "To view live server logs, run:"
    echo "  sudo journalctl -u minecraft -f"
else
    echo "❌ Server failed to start! Check logs:"
    echo "  sudo journalctl -u minecraft -e"
fi
