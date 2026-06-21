#!/usr/bin/env bash

PORT="25565"

echo "🌍 Public Addresses (Internet):"
# Set max-time to prevent hanging if IPv6 is misconfigured
PUBLIC_IPV4=$(curl -4 -s --max-time 3 ifconfig.me || echo "")
PUBLIC_IPV6=$(curl -6 -s --max-time 3 ifconfig.me || echo "")

if [ -n "$PUBLIC_IPV4" ]; then
    echo "  - IPv4: $PUBLIC_IPV4:$PORT"
fi
if [ -n "$PUBLIC_IPV6" ]; then
    echo "  - IPv6: [$PUBLIC_IPV6]:$PORT"
fi
if [ -z "$PUBLIC_IPV4" ] && [ -z "$PUBLIC_IPV6" ]; then
    echo "  - (Could not resolve public IP)"
fi

echo ""
echo "🏠 Local & VPN Addresses (LAN / Tailscale / Docker):"

# IPv4 Addresses (exclude loopback)
ip -o -4 addr show | awk '{print $2, $4}' | grep -v "^lo" | while read -r iface cidr; do
    ip="${cidr%/*}"
    # Highlight Tailscale interfaces
    if [[ "$iface" == "tailscale0" ]]; then
        echo "  - $iface (VPN): $ip:$PORT 🚀"
    else
        echo "  - $iface (IPv4): $ip:$PORT"
    fi
done

# IPv6 Addresses (exclude loopback and fe80 link-local)
ip -o -6 addr show | awk '{print $2, $4}' | grep -v "^lo" | grep -v " fe80" | while read -r iface cidr; do
    ip="${cidr%/*}"
    if [[ "$iface" == "tailscale0" ]]; then
        echo "  - $iface (VPN): [$ip]:$PORT 🚀"
    else
        echo "  - $iface (IPv6): [$ip]:$PORT"
    fi
done
