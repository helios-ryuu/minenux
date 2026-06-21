#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE=""
AUTO_CONFIRM=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift ;;
        -y|--yes) AUTO_CONFIRM=true ;;
    esac
    shift
done

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# We need jq/curl early to parse config and resolve API versions,
# openssl to generate the RCON password, python3 to run lib/rcon.py later.
apt update && apt install -y curl jq openssl python3

source "$DIR/lib/common.sh"

# --- PRE-FLIGHT CHECK: Ghost Processes & Existing Installs ---
echo "Running Pre-flight system checks..."
ORPHAN_PIDS=$(pgrep -f "java.*server.jar" || true)
if [ -n "$ORPHAN_PIDS" ]; then
    echo "⚠️  CRITICAL: Found running Minecraft instance(s) [PID: $(echo $ORPHAN_PIDS | tr '\n' ' ')]."
    echo "Continuing will cause port conflicts and memory allocation failures."
    read -p "Kill these processes automatically before proceeding? [Y/n]: " KILL_PROCEED
    if [[ ! "$KILL_PROCEED" =~ ^[Nn] ]]; then
        pkill -f "java.*server.jar"
        sleep 2
        echo "Processes terminated."
    else
        echo "Installation aborted to protect existing processes."
        exit 1
    fi
fi

if [ -d "/opt/minecraft/server" ] && [ "$AUTO_CONFIRM" = false ]; then
    echo "⚠️  WARNING: Existing installation detected at /opt/minecraft/server."
    echo "Running setup over an existing install may corrupt configurations or World locks."
    read -p "Do you want to run uninstall.sh first to start fresh? [Y/n/Skip]: " WIPE_PROCEED
    if [[ "$WIPE_PROCEED" =~ ^[Yy] || -z "$WIPE_PROCEED" ]]; then
        if [ -f "$DIR/uninstall.sh" ]; then
            bash "$DIR/uninstall.sh"
            echo "Cleanup complete. Resuming setup..."
        else
            echo "uninstall.sh not found. Aborting."
            exit 1
        fi
    elif [[ "$WIPE_PROCEED" =~ ^[Nn] ]]; then
        echo "Aborted setup by user."
        exit 1
    fi
    # If user types "Skip", setup continues over the existing files
fi
# --- END PRE-FLIGHT CHECK ---

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
    RCON_PORT=$(jq -r '.rcon.port // 25575' "$CONFIG_FILE")
    LEVEL_NAME=$(jq -r '.initial_map.name // "world"' "$CONFIG_FILE")
    SEED_MODE=$(jq -r '.initial_map.seed_mode // "random"' "$CONFIG_FILE")
    LEVEL_SEED=$(jq -r '.initial_map.seed // empty' "$CONFIG_FILE")
    GMODE=$(jq -r '.initial_map.gamemode // "survival"' "$CONFIG_FILE")
    GAMERULES_JSON=$(jq -c '.initial_map.gamerules // {}' "$CONFIG_FILE")

    # Require variables are set
    if [ -z "$JAVA_VER" ] || [ -z "$MC_VER" ]; then
         echo "Error parsing config file"
         exit 1
    fi
    [ "$SEED_MODE" == "random" ] && LEVEL_SEED=""
else
    read -p "Enter Target Java Version (Headless) [25]: " JAVA_VER
    JAVA_VER=${JAVA_VER:-25}

    read -p "Enter Dedicated System User [minenux]: " MC_USER
    MC_USER=${MC_USER:-minenux}

    read -p "Enter Install Directory [/opt/minecraft/server]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/opt/minecraft/server}

    read -p "Enter Minecraft Version [latest]: " MC_VER
    MC_VER=${MC_VER:-latest}

    read -p "Enter Fabric Loader Version [latest]: " FABRIC_VER
    FABRIC_VER=${FABRIC_VER:-latest}

    read -p "Enter Fabric Installer Version [latest]: " INSTALLER_VER
    INSTALLER_VER=${INSTALLER_VER:-latest}

    read -p "Enter RAM Allocation (e.g., 8G) [8G]: " RAM
    RAM=${RAM:-8G}

    echo ""
    echo "--- Online Mode (Authentication) ---"
    echo "* true  : Premium accounts only (Secure). Best for PUBLIC servers."
    echo "* false : Allows Cracked/Offline accounts. Best for PRIVATE/LAN servers with friends."
    echo "          (Warning: If false, anyone can login with your admin name. Install an Auth mod to protect!)"
    read -p "Enable Online Mode? (true/false) [false]: " ONLINE_MODE
    ONLINE_MODE=${ONLINE_MODE:-false}
    echo ""

    read -p "Max Players? [20]: " MAX_PLAYERS
    MAX_PLAYERS=${MAX_PLAYERS:-20}

    read -p "RCON port (used internally by server-up.sh/server-down.sh/list-map.sh) [25575]: " RCON_PORT
    RCON_PORT=${RCON_PORT:-25575}

    echo ""
    echo "--- Initial Map ---"
    read -p "Initial map name [world]: " LEVEL_NAME
    LEVEL_NAME=${LEVEL_NAME:-world}

    read -p "Select Gamemode (survival/creative/adventure/spectator) [survival]: " GMODE
    GMODE=${GMODE:-survival}
    if [[ ! "$GMODE" =~ ^(survival|creative|adventure|spectator)$ ]]; then
        echo "Invalid gamemode. Defaulting to survival."
        GMODE="survival"
    fi

    LEVEL_SEED=$(prompt_seed)
    GAMERULES_JSON=$(prompt_gamerules)
fi

# Resolve "latest" to actual versions via Fabric Meta API
if [ "$MC_VER" == "latest" ]; then
    echo "Resolving latest stable Minecraft version..."
    MC_VER=$(curl -s "https://meta.fabricmc.net/v2/versions/game" | jq -r '[.[] | select(.stable == true)][0].version')
fi

if [ "$FABRIC_VER" == "latest" ]; then
    echo "Resolving latest stable Fabric Loader version..."
    FABRIC_VER=$(curl -s "https://meta.fabricmc.net/v2/versions/loader" | jq -r '[.[] | select(.stable == true)][0].version')
fi

if [ "$INSTALLER_VER" == "latest" ]; then
    echo "Resolving latest stable Fabric Installer version..."
    INSTALLER_VER=$(curl -s "https://meta.fabricmc.net/v2/versions/installer" | jq -r '[.[] | select(.stable == true)][0].version')
fi

echo "Target Versions -> Game: $MC_VER | Loader: $FABRIC_VER | Installer: $INSTALLER_VER"

if [ "$AUTO_CONFIRM" = false ]; then
    echo "========================================="
    echo "Review your configuration:"
    echo "- Java Version:    $JAVA_VER"
    echo "- User:            $MC_USER"
    echo "- Install Dir:     $INSTALL_DIR"
    echo "- Game Version:    $MC_VER"
    echo "- Fabric Version:  $FABRIC_VER"
    echo "- Installer Ver:   $INSTALLER_VER"
    echo "- RAM:             $RAM"
    echo "- Online Mode:     $ONLINE_MODE"
    echo "- Max Players:     $MAX_PLAYERS"
    echo "- RCON Port:       $RCON_PORT"
    echo "- Initial Map:     $LEVEL_NAME"
    echo "- Gamemode:        $GMODE"
    echo "- Seed:            ${LEVEL_SEED:-<random>}"
    echo "- Game Rules:      $GAMERULES_JSON"
    echo "========================================="
    read -p "Proceed with these settings? [Y/n]: " CONFIRM_PROCEED
    if [[ "$CONFIRM_PROCEED" =~ ^[Nn] ]]; then
        echo "Aborted by user."
        exit 0
    fi
fi

echo "=== Phase 1: Environment & Dependencies ==="
apt install -y wget git nano ufw tar

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

echo "Accepting EULA..."
su - "$MC_USER" -c "echo 'eula=true' > '$INSTALL_DIR/eula.txt'"

if [ ! -f "$INSTALL_DIR/server.properties" ]; then
    echo "Error: server.properties was not generated by the dry-run. Aborting."
    exit 1
fi

echo "=== Phase 4: Server Properties, RCON & Initial Map ==="
RCON_PASSWORD=$(gen_rcon_password)

prop_set online-mode "$ONLINE_MODE"
prop_set max-players "$MAX_PLAYERS"
prop_set level-name "$LEVEL_NAME"
prop_set level-seed "$LEVEL_SEED"
prop_set gamemode "$GMODE"
prop_set enable-rcon "true"
prop_set "rcon.port" "$RCON_PORT"
prop_set "rcon.password" "$RCON_PASSWORD"
prop_set broadcast-rcon-to-ops "false"
# RCON is bound to 127.0.0.1 only by the management scripts (they never pass
# a non-localhost host to rcon.py) - so it never needs to be opened in UFW.

mkdir -p "$INSTALL_DIR/$LEVEL_NAME"
jq -n --arg seed "$LEVEL_SEED" --arg gm "$GMODE" --argjson rules "$GAMERULES_JSON" --arg created "$(date -Iseconds)" \
    '{seed: $seed, gamemode: $gm, created_at: $created, gamerules: $rules, gamerules_applied: false}' \
    > "$INSTALL_DIR/$LEVEL_NAME/.minenux-meta.json"
chown -R "$MC_USER":"$MC_USER" "$INSTALL_DIR/$LEVEL_NAME"

echo "=== Phase 5: Optimization & Daemonization ==="
# Note: named run-server.sh (not server-up.sh) deliberately - keeps it distinct
# from the top-level management wrapper ./server-up.sh that calls systemctl + ip.sh.
RUN_SH="$INSTALL_DIR/run-server.sh"
cat << 'EOF' > "$RUN_SH"
#!/usr/bin/env bash

# Fixed memory allocation for optimization
MEM_ALLOC="ALLOC_PLACEHOLDER"

java -Xms${MEM_ALLOC} -Xmx${MEM_ALLOC} \
  -XX:+UseZGC \
  -XX:+AlwaysPreTouch \
  -XX:+DisableExplicitGC \
  -XX:+PerfDisableSharedMem \
  -jar server.jar nogui
EOF

sed -i "s/ALLOC_PLACEHOLDER/$RAM/" "$RUN_SH"
chmod +x "$RUN_SH"
chown "$MC_USER":"$MC_USER" "$RUN_SH"

SERVICE_FILE="/etc/systemd/system/minecraft.service"
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Minecraft Server (By Minenux)
After=network.target

[Service]
User=$MC_USER
Group=$MC_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$RUN_SH

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

echo ""
echo "========================================="
echo "Setup Complete!"
echo "- Map '$LEVEL_NAME' will be generated on first boot (seed: ${LEVEL_SEED:-random})."
echo "- Gamerules are saved and will auto-apply via RCON once the world finishes generating."
echo "- RCON listens on 127.0.0.1:$RCON_PORT only - used internally by server-up.sh / server-down.sh / list-map.sh."
echo "Run: sudo ./server-up.sh   to launch the server."
echo "========================================="
