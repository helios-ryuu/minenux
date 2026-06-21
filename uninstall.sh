#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
require_root

echo "--- Minenux Uninstall Script ---"
read -p "WARNING: This will permanently delete the Minecraft server, ALL maps, the dedicated user, and configuration. Are you sure? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo "[1/5] Stopping and disabling systemd service..."
systemctl stop minecraft || true
systemctl disable minecraft || true
rm -f /etc/systemd/system/minecraft.service
systemctl daemon-reload

echo "[2/5] Hunting and terminating orphan Java processes..."
# Xóa sạch các tiến trình bị kẹt từ user MC_USER hoặc có string trùng khớp
pkill -u "$MC_USER" -f java >/dev/null 2>&1 || true
pkill -f "java.*server.jar" >/dev/null 2>&1 || true
sleep 1

echo "[3/5] Removing UFW firewall rule..."
ufw delete allow 25565/tcp >/dev/null 2>&1 || true

echo "[4/5] Deleting installation directory and all maps..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Deleted $INSTALL_DIR"
fi

echo "[5/5] Removing dedicated user..."
if id "$MC_USER" &>/dev/null; then
    userdel -r "$MC_USER" 2>/dev/null || true
    groupdel "$MC_USER" 2>/dev/null || true
    echo "Deleted user $MC_USER"
fi

echo "--- Uninstallation Complete ---"
echo "Note: Java (openjdk-headless) was NOT removed automatically."
echo "If you want to manually remove Java, run: sudo apt autoremove --purge openjdk-*-jdk-headless"