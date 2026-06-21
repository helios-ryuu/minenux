#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

CONFIG_FILE=""
if [ "$1" == "--config" ] && [ -n "$2" ]; then
    CONFIG_FILE="$2"
fi

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "=== Phase 1: Environment & Dependencies ==="
apt update && apt upgrade -y
apt install -y curl wget git nano ufw tar jq

# Variables
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    JAVA_VER=$(jq -r '.system.java_version' "$CONFIG_FILE")
    MC_USER=$(jq -r '.system.mc_user' "$CONFIG_FILE")
    INSTALL_DIR=$(jq -r '.system.install_dir' "$CONFIG_FILE")
    MC_VER=$(jq -r '.minecraft.mc_version' "$CONFIG_FILE")
    FABRIC_VER=$(jq -r '.minecraft.fabric_version' "$CONFIG_FILE")
    INSTALLER_VER=$(jq -r '.minecraft.installer_version' "$CONFIG_FILE")
    RAM=$(jq -r '.minecraft.memory_alloc' "$CONFIG_FILE")
    ONLINE_MODE=$(jq -r '.server."online-mode"' "$CONFIG_FILE")
    MAX_PLAYERS=$(jq -r '.server."max-players"' "$CONFIG_FILE")
else
    read -p "Enter Target Java Version (Headless) [25]: " JAVA_VER
    JAVA_VER=${JAVA_VER:-25}
    
    read -p "Enter Dedicated System User [minenux]: " MC_USER
    MC_USER=${MC_USER:-minenux}
    
    read -p "Enter Install Directory [/opt/minecraft/server]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/opt/minecraft/server}
    
    read -p "Enter Minecraft Version [26.2]: " MC_VER
    MC_VER=${MC_VER:-26.2}
    
    read -p "Enter Fabric Loader Version [0.19.3]: " FABRIC_VER
    FABRIC_VER=${FABRIC_VER:-0.19.3}
    
    read -p "Enter Fabric Installer Version [1.1.1]: " INSTALLER_VER
    INSTALLER_VER=${INSTALLER_VER:-1.1.1}
    
    read -p "Enter RAM Allocation (e.g., 8G) [8G]: " RAM
    RAM=${RAM:-8G}

    read -p "Enable Online Mode? (true/false) [false]: " ONLINE_MODE
    ONLINE_MODE=${ONLINE_MODE:-false}
    
    read -p "Max Players? [20]: " MAX_PLAYERS
    MAX_PLAYERS=${MAX_PLAYERS:-20}
fi

echo "Installing OpenJDK $JAVA_VER Headless..."
apt install -y "openjdk-${JAVA_VER}-jdk-headless"

echo "Creating unprivileged user '$MC_USER'..."
id -u "$MC_USER" &>/dev/null || useradd -r -m -U -d "$INSTALL_DIR" -s /bin/bash "$MC_USER"

mkdir -p "$INSTALL_DIR"
chown -R "$MC_USER":"$MC_USER" "$INSTALL_DIR"

echo "=== Phase 2: Minecraft & Fabric Bootstrapping ==="
su - "$MC_USER" -c "mkdir -p '$INSTALL_DIR/mods'"

echo "Downloading Fabric bundle server.jar..."
DOWNLOAD_URL="https://meta.fabricmc.net/v2/versions/loader/${MC_VER}/${FABRIC_VER}/${INSTALLER_VER}/server/jar"
su - "$MC_USER" -c "curl -o '$INSTALL_DIR/server.jar' '$DOWNLOAD_URL'"

echo "=== Phase 3: Dry-Run & Configuration ==="
echo "Running dummy boot to extract properties..."
su - "$MC_USER" -c "cd '$INSTALL_DIR' && java -jar server.jar nogui || true"

# Modifying server.properties
if [ -f "$INSTALL_DIR/server.properties" ]; then
    sed -i "s/^online-mode=.*/online-mode=$ONLINE_MODE/" "$INSTALL_DIR/server.properties"
    sed -i "s/^max-players=.*/max-players=$MAX_PLAYERS/" "$INSTALL_DIR/server.properties"
fi

echo "Accepting EULA..."
su - "$MC_USER" -c "echo 'eula=true' > '$INSTALL_DIR/eula.txt'"

echo "=== Phase 4: Optimization & Daemonization ==="
START_SH="$INSTALL_DIR/start.sh"
cat << 'EOF' > "$START_SH"
#!/usr/bin/env bash

# Fixed memory allocation for optimization
MEM_ALLOC="ALLOC_PLACEHOLDER"

java -Xms${MEM_ALLOC} -Xmx${MEM_ALLOC} \
  -XX:+UseZGC \
  -XX:+ZGenerational \
  -XX:+AlwaysPreTouch \
  -XX:+DisableExplicitGC \
  -XX:+PerfDisableSharedMem \
  -jar server.jar nogui
EOF

sed -i "s/ALLOC_PLACEHOLDER/$RAM/" "$START_SH"
chmod +x "$START_SH"
chown "$MC_USER":"$MC_USER" "$START_SH"

SERVICE_FILE="/etc/systemd/system/minecraft.service"
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Minecraft Server (By Minenux)
After=network.target

[Service]
User=$MC_USER
Group=$MC_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$START_SH

Restart=on-failure
RestartSec=20s
KillMode=process
StandardInput=null

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minecraft

echo "Allowing UFW Port 25565/tcp..."
ufw allow 25565/tcp >/dev/null 2>&1

echo "Setup Complete! To start the server, run: sudo systemctl start minecraft"
