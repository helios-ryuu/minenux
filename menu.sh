#!/usr/bin/env bash
# menu.sh - Main interactive console menu for Minenux management

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

print_menu_header() {
    echo ""
    echo "============================================================"
    echo "                 Minenux Control Center                     "
    echo "============================================================"
}

while true; do
    print_menu_header
    
    # Detect current status of the server
    CURRENT_MAP=$(prop_get level-name)
    if is_server_running; then
        echo "Server Status: 🟢 RUNNING (Map: $CURRENT_MAP)"
    else
        echo "Server Status: 🛑 STOPPED (Selected Map: ${CURRENT_MAP:-None})"
    fi
    echo "------------------------------------------------------------"
    echo "1) Setup / Reinstall Server"
    echo "2) Start Server (Up)"
    echo "3) Stop Server (Down)"
    echo "4) Restart Server"
    echo "5) Get Connection IP"
    echo "6) Manage Maps (map.sh)"
    echo "7) Uninstall Minenux"
    echo "8) Exit"
    echo "------------------------------------------------------------"
    read -p "Choose an option: " opt
    case $opt in
        1)
            sudo "$DIR/setup.sh"
            ;;
        2)
            sudo "$DIR/up.sh"
            ;;
        3)
            sudo "$DIR/down.sh"
            ;;
        4)
            echo "Restarting Minecraft Server..."
            sudo "$DIR/down.sh"
            sudo "$DIR/up.sh"
            ;;
        5)
            "$DIR/ip.sh"
            ;;
        6)
            sudo "$DIR/map.sh"
            ;;
        7)
            sudo "$DIR/uninstall.sh"
            exit 0
            ;;
        8)
            echo "Bye."
            exit 0
            ;;
        *)
            echo "❌ Invalid option."
            ;;
    esac
done
