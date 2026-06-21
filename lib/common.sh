#!/usr/bin/env bash
# lib/common.sh - shared functions sourced by every Minenux management script.
# Not meant to be executed directly.

INSTALL_DIR="${INSTALL_DIR:-/opt/minecraft/server}"
MC_USER="${MC_USER:-minenux}"
SERVICE_NAME="minecraft"

# Curated gamerule set + vanilla defaults, shared between setup.sh (initial map)
# and list-map.sh (new map / live edit).
GAMERULE_KEYS=(keepInventory doDaylightCycle doMobSpawning mobGriefing doFireTick announceAdvancements)
GAMERULE_DEFAULTS=(false true true true true true)

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root (sudo)"
        exit 1
    fi
}

gen_rcon_password() {
    openssl rand -hex 16 2>/dev/null || tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24
}

# --- server.properties accessors -------------------------------------------------

prop_get() {
    # prop_get <key>
    grep "^${1}=" "$INSTALL_DIR/server.properties" 2>/dev/null | head -n1 | cut -d= -f2-
}

prop_set() {
    # prop_set <key> <value>
    # Implemented with awk (not sed) so values containing '|', '&', '.', etc.
    # (e.g. an arbitrary world seed) can never break the replacement pattern.
    local key="$1" val="$2" file="$INSTALL_DIR/server.properties" tmp
    tmp=$(mktemp)
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        awk -F= -v k="$key" -v v="$val" 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' "$file" > "$tmp"
    else
        cp "$file" "$tmp"
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
    fi
    mv "$tmp" "$file"
    chown "$MC_USER":"$MC_USER" "$file" 2>/dev/null
    chmod 640 "$file" 2>/dev/null
}

# --- RCON --------------------------------------------------------------------------

rcon_ready() {
    [ "$(prop_get enable-rcon)" == "true" ] && [ -n "$(prop_get rcon.password)" ]
}

rcon_exec() {
    # rcon_exec [--wait] <command...>
    local script_dir wait_flag=()
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$1" == "--wait" ]; then
        wait_flag=(--wait)
        shift
    fi
    python3 "$script_dir/rcon.py" "${wait_flag[@]}" 127.0.0.1 "$(prop_get rcon.port)" "$(prop_get rcon.password)" "$@"
}

# --- service helpers -----------------------------------------------------------------

is_server_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
}

graceful_stop() {
    if is_server_running; then
        if rcon_ready; then
            echo "Saving world and stopping gracefully via RCON (save-all + stop)..."
            rcon_exec "save-all" "stop" &> /dev/null || true
            sleep 5
        fi
        systemctl stop "$SERVICE_NAME"
        local tries=0
        while is_server_running && [ $tries -lt 15 ]; do
            sleep 2
            tries=$((tries + 1))
        done
    fi
}

# --- map / world helpers -------------------------------------------------------------

list_world_folders() {
    # Any direct subdirectory of INSTALL_DIR containing level.dat is a valid map.
    find "$INSTALL_DIR" -maxdepth 2 -name "level.dat" -printf '%h\n' 2>/dev/null | xargs -n1 basename | sort
}

apply_pending_gamerules() {
    local map_name="$1"
    local meta_file="$INSTALL_DIR/$map_name/.minenux-meta.json"
    [ -f "$meta_file" ] || return 0

    local applied
    applied=$(jq -r '.gamerules_applied // false' "$meta_file" 2>/dev/null)

    echo "Waiting for RCON to come online for map '$map_name' telemetry..."
    if ! rcon_exec --wait "list" &> /dev/null; then
        echo "⚠️  Could not reach RCON; background tasks aborted."
        return 1
    fi

    # 1. TỰ ĐỘNG TRÍCH XUẤT SEED (Zero-Dependency)
    local current_seed=$(jq -r '.seed // empty' "$meta_file" 2>/dev/null)
    if [ "$current_seed" == "imported" ] || [ "$current_seed" == "pending" ]; then
        local rcon_seed_out=$(rcon_exec "seed" 2>/dev/null)
        # Bắt chuỗi định dạng: "Seed: [123456789]"
        local real_seed=$(echo "$rcon_seed_out" | sed -n 's/.*Seed: \[\(.*\)\].*/\1/p' | tr -d '\r')
        if [ -n "$real_seed" ]; then
            local tmp_seed=$(jq --arg s "$real_seed" '.seed = $s' "$meta_file")
            echo "$tmp_seed" > "$meta_file"
            echo "✅ Auto-detected true seed '$real_seed' via RCON telemetry."
        fi
    fi

    # 2. ÁP DỤNG GAMERULES (Chỉ chạy 1 lần)
    if [ "$applied" != "true" ]; then
        local rules
        rules=$(jq -r '.gamerules // {} | to_entries[] | "\(.key) \(.value)"' "$meta_file" 2>/dev/null)
        while IFS= read -r rule; do
            [ -z "$rule" ] && continue
            rcon_exec "gamerule $rule" &> /dev/null
        done <<< "$rules"

        local tmp_rules=$(jq '.gamerules_applied = true' "$meta_file")
        echo "$tmp_rules" > "$meta_file"
        echo "✅ Gamerules applied successfully."
    fi
    
    chown "$MC_USER":"$MC_USER" "$meta_file" 2>/dev/null
}

# --- interactive prompts (used by setup.sh and list-map.sh) --------------------------

prompt_seed() {
    # Prints the chosen seed to stdout (empty string = random). All prompt text
    # goes to stderr so callers can safely capture stdout via $(...).
    echo "--- World Seed ---" >&2
    echo "  1) Random seed" >&2
    echo "  2) Custom seed" >&2
    read -p "Select [1]: " choice
    choice=${choice:-1}
    if [ "$choice" == "2" ]; then
        read -p "Enter seed: " seed
        echo "$seed"
    else
        echo ""
    fi
}

prompt_gamerules() {
    # Prints a JSON object {"rule":"value",...} to stdout.
    echo "--- Game Rules (Enter to keep default) ---" >&2
    local json="{}"
    for i in "${!GAMERULE_KEYS[@]}"; do
        local key="${GAMERULE_KEYS[$i]}"
        local def="${GAMERULE_DEFAULTS[$i]}"
        local val
        read -p "  $key [$def]: " val
        val=${val:-$def}
        json=$(jq -c --arg k "$key" --arg v "$val" '. + {($k): $v}' <<< "$json")
    done
    echo "$json"
}
