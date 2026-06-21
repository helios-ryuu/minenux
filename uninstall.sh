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

echo "[1/4] Stopping and disabling systemd service..."
systemctl stop minecraft || true
systemctl disable minecraft || true
rm -f /etc/systemd/system/minecraft.service
systemctl daemon-reload

echo "[2/4] Removing UFW firewall rule..."
ufw delete allow 25565/tcp >/dev/null 2>&1 || true

echo "[3/4] Deleting installation directory and all maps..."
# INSTALL_DIR / MC_USER come from lib/common.sh (default /opt/minecraft/server
# and minenux). Override with env vars if you customized them during setup,
# e.g.: INSTALL_DIR=/srv/mc MC_USER=mcadmin ./uninstall.sh
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Deleted $INSTALL_DIR"
fi

echo "[4/4] Removing dedicated user..."
if id "$MC_USER" &>/dev/null; then
    userdel -r "$MC_USER" 2>/dev/null || true
    groupdel "$MC_USER" 2>/dev/null || true
    echo "Deleted user $MC_USER"
fi

echo "--- Uninstallation Complete ---"
echo "Note: Java (openjdk-headless) was NOT removed automatically in case it's used by other software."
echo "If you want to manually remove Java, run: sudo apt autoremove --purge openjdk-*-jdk-headless"
echo "Note: this management toolkit itself ($DIR) was left untouched - remove it manually if no longer needed."
