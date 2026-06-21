#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

PORT=$(prop_get server-port)
PORT=${PORT:-25565}

echo "=== Connection Info ==="

if command -v tailscale &> /dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null)
    if [ -n "$TS_IP" ]; then
        echo "Tailscale (recommended, zero exposed ports): $TS_IP:$PORT"
    fi
fi

LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$LAN_IP" ] && echo "LAN IP: $LAN_IP:$PORT"

echo "========================"
