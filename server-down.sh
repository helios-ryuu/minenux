#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
require_root

echo "Stopping Minecraft Server..."
graceful_stop

if ! is_server_running; then
    echo "🛑 Server successfully stopped."
else
    echo "⚠️ Warning: The server process may still be stopping or hanging. Check with:"
    echo "  sudo systemctl status minecraft"
fi
