#!/usr/bin/env bash

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "--- Minenux Uninstall Script ---"
read -p "WARNING: This will permanently delete the Minecraft server, world, user, and configuration. Are you sure? [y/N]: " CONFIRM
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

echo "[3/4] Deleting installation directory and data..."
# Use default path or prompt if not standard
INSTALL_DIR="/opt/minecraft/server"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Deleted $INSTALL_DIR"
fi

echo "[4/4] Removing dedicated user..."
# Default user minenux
USER="minenux"
if id "$USER" &>/dev/null; then
    userdel -r "$USER" 2>/dev/null || true
    groupdel "$USER" 2>/dev/null || true
    echo "Deleted user $USER"
fi

echo "--- Uninstallation Complete ---"
echo "Note: Java (openjdk-headless) was NOT removed automatically in case it's used by other software."
echo "If you want to manually remove Java, run: sudo apt autoremove --purge openjdk-*-jdk-headless"
