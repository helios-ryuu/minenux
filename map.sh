#!/usr/bin/env bash
# list-map.sh - interactive map manager.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

require_root

print_header() {
    echo ""
    echo "============================================================"
    echo " Minenux Map Manager  -  $INSTALL_DIR"
    echo "============================================================"
}

show_map_list() {
    local current_level running
    current_level=$(prop_get level-name)
    running=false
    is_server_running && running=true

    printf "\n%-3s %-20s %-22s %-10s %s\n" "#" "MAP NAME" "STATUS" "SIZE" "SEED"
    echo "------------------------------------------------------------------------"

    MAPS=()
    local i=1
    while IFS= read -r map; do
        [ -z "$map" ] && continue
        MAPS+=("$map")
        local status size seed meta
        meta="$INSTALL_DIR/$map/.minenux-meta.json"
        size=$(du -sh "$INSTALL_DIR/$map" 2>/dev/null | cut -f1)
        seed="-"
        if [ -f "$meta" ]; then
            seed=$(jq -r '.seed // empty' "$meta" 2>/dev/null)
        fi
        [ -z "$seed" ] && seed="random"

        if [ "$map" == "$current_level" ] && [ "$running" == true ]; then
            status="🟢 ACTIVE (running)"
        elif [ "$map" == "$current_level" ]; then
            status="🟡 SELECTED (stopped)"
        else
            status="⚪ INACTIVE"
        fi
        printf "%-3s %-20s %-22s %-10s %s\n" "$i" "$map" "$status" "$size" "$seed"
        i=$((i + 1))
    done < <(list_world_folders)

    if [ ${#MAPS[@]} -eq 0 ]; then
        echo "(no maps found yet - has the server been started at least once?)"
    fi
}

action_switch() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to activate: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then echo "Invalid selection."; return; fi

    local current=$(prop_get level-name)
    if [ "$target" == "$current" ]; then echo "'$target' is already the selected map."; return; fi

    local meta="$INSTALL_DIR/$target/.minenux-meta.json"
    local gmode=$(jq -r '.gamemode // "survival"' "$meta" 2>/dev/null)
    local cheats=$(jq -r '.cheats // "false"' "$meta" 2>/dev/null)

    echo "Switching active map: $current -> $target"
    graceful_stop
    
    prop_set level-name "$target"
    prop_set gamemode "$gmode"
    prop_set allow-flight "$cheats"
    prop_set enable-command-block "$cheats"
    
    echo "Starting server with map '$target' (Mode: $gmode, Cheats: $cheats)..."
    systemctl start minecraft
    apply_pending_gamerules "$target"
    echo "✅ Server is now running map '$target'."
}

action_create() {
    read -p $'\nNew map name (letters, numbers, dash, underscore): ' name
    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "Invalid name."; return; fi
    if [ -d "$INSTALL_DIR/$name" ]; then echo "A map named '$name' already exists."; return; fi

    local seed rules gmode cheats
    
    read -p "Select gamemode (survival/creative/adventure/spectator) [survival]: " gmode
    gmode=${gmode:-survival}
    if [[ ! "$gmode" =~ ^(survival|creative|adventure|spectator)$ ]]; then
        echo "Invalid gamemode. Defaulting to survival."
        gmode="survival"
    fi

    read -p "Allow cheats? (enables flight & command blocks) (true/false) [false]: " cheats
    cheats=${cheats:-false}
    if [[ ! "$cheats" =~ ^(true|false)$ ]]; then cheats="false"; fi

    seed=$(prompt_seed)
    rules=$(prompt_gamerules)

    graceful_stop
    mkdir -p "$INSTALL_DIR/$name"
    chown -R "$MC_USER":"$MC_USER" "$INSTALL_DIR/$name"

    jq -n --arg seed "$seed" --arg gm "$gmode" --arg ch "$cheats" --argjson rules "$rules" --arg created "$(date -Iseconds)" \
        '{seed: $seed, gamemode: $gm, cheats: $ch, created_at: $created, gamerules: $rules, gamerules_applied: false}' \
        > "$INSTALL_DIR/$name/.minenux-meta.json"
    chown "$MC_USER":"$MC_USER" "$INSTALL_DIR/$name/.minenux-meta.json"

    prop_set level-name "$name"
    prop_set level-seed "$seed"
    prop_set gamemode "$gmode"
    prop_set allow-flight "$cheats"
    prop_set enable-command-block "$cheats"

    echo "Starting server to generate world '$name'..."
    systemctl start minecraft
    apply_pending_gamerules "$name"
    echo "✅ Map '$name' created (Mode: $gmode, Cheats: $cheats)."
}

action_edit_gamerules() {
    local current meta json current_gm new_gm current_ch new_ch
    current=$(prop_get level-name)
    if ! is_server_running; then
        echo "Server must be running to edit live settings. Switch to / start a map first."
        return
    fi

    meta="$INSTALL_DIR/$current/.minenux-meta.json"
    echo "Editing settings for active map '$current' (Enter to keep current value)."
    
    current_gm=$(jq -r '.gamemode // "survival"' "$meta" 2>/dev/null)
    read -p "  gamemode [$current_gm]: " new_gm
    new_gm=${new_gm:-$current_gm}
    if [[ "$new_gm" =~ ^(survival|creative|adventure|spectator)$ ]]; then
        rcon_exec "defaultgamemode $new_gm" &> /dev/null
        prop_set gamemode "$new_gm"
    else
        echo "  -> Invalid gamemode. Keeping '$current_gm'."
        new_gm="$current_gm"
    fi

    current_ch=$(jq -r '.cheats // "false"' "$meta" 2>/dev/null)
    read -p "  allow cheats (flight/cmd-blocks) [$current_ch]: " new_ch
    new_ch=${new_ch:-$current_ch}
    if [[ "$new_ch" =~ ^(true|false)$ ]]; then
        prop_set allow-flight "$new_ch"
        prop_set enable-command-block "$new_ch"
    else
        echo "  -> Invalid cheat flag. Keeping '$current_ch'."
        new_ch="$current_ch"
    fi

    json="{}"
    for i in "${!GAMERULE_KEYS[@]}"; do
        local key="${GAMERULE_KEYS[$i]}"
        local now val
        now=$(rcon_exec "gamerule $key" 2>/dev/null | sed -n 's/.*is currently set to: //p' | tr -d '\r')
        [ -z "$now" ] && now="${GAMERULE_DEFAULTS[$i]}"
        read -p "  $key [$now]: " val
        val=${val:-$now}
        rcon_exec "gamerule $key $val" &> /dev/null
        json=$(jq -c --arg k "$key" --arg v "$val" '. + {($k): $v}' <<< "$json")
    done

    if [ -f "$meta" ]; then
        local tmp
        tmp=$(jq --argjson rules "$json" --arg gm "$new_gm" --arg ch "$new_ch" \
            '.gamerules = $rules | .gamemode = $gm | .cheats = $ch' "$meta")
        echo "$tmp" > "$meta"
        chown "$MC_USER":"$MC_USER" "$meta" 2>/dev/null
    fi
    echo "✅ Live settings updated and persisted."
}

action_rename() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to rename: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then echo "Invalid selection."; return; fi
    if [ "$target" == "$(prop_get level-name)" ] && is_server_running; then
        echo "Stop the server (or switch off this map) before renaming it."
        return
    fi
    read -p "New name for '$target': " newname
    if [[ ! "$newname" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "Invalid name."; return; fi
    if [ -d "$INSTALL_DIR/$newname" ]; then echo "Name already in use."; return; fi

    mv "$INSTALL_DIR/$target" "$INSTALL_DIR/$newname"
    if [ "$target" == "$(prop_get level-name)" ]; then
        prop_set level-name "$newname"
    fi
    echo "✅ Renamed '$target' to '$newname'."
}

action_export() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to EXPORT: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then echo "Invalid selection."; return; fi

    local real_home
    if [ -n "$SUDO_USER" ]; then
        real_home=$(eval echo ~"$SUDO_USER")
    else
        real_home="$HOME"
    fi

    local default_dest="$real_home/minenux_exports"
    read -p "Enter destination directory [$default_dest]: " dest_dir
    dest_dir="${dest_dir:-$default_dest}"
    dest_dir="${dest_dir/#\~/$real_home}"

    mkdir -p "$dest_dir"
    if [ -n "$SUDO_USER" ]; then chown -R "$SUDO_USER":"$SUDO_USER" "$dest_dir"; fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive="$dest_dir/${target}_${timestamp}.tar.gz"

    echo "Flushing world data to disk..."
    if is_server_running && [ "$target" == "$(prop_get level-name)" ]; then
        rcon_exec "save-all" > /dev/null 2>&1
        sleep 2
    fi

    echo "Preparing export payload in isolated staging area..."
    local staging_dir=$(mktemp -d)
    cp -r "$INSTALL_DIR/$target" "$staging_dir/"

    # --- BẮT ĐẦU NBT TRANSFORMER HOOK ---
    local player_dir="$staging_dir/$target/playerdata"
    if [ -d "$player_dir" ]; then
        # Truy xuất UUID file mới nhất (đại diện cho host player)
        local latest_player=$(ls -t "$player_dir/"*.dat 2>/dev/null | head -n 1)
        local level_dat="$staging_dir/$target/level.dat"
        
        if [ -n "$latest_player" ] && [ -f "$level_dat" ]; then
            echo "Injecting Player UUID data into level.dat for Singleplayer compatibility..."
            
            # Ưu tiên sử dụng venv nếu đã được cài đặt, fallback về python3 hệ thống
            local py_bin="python3"
            [ -x "$INSTALL_DIR/venv/bin/python3" ] && py_bin="$INSTALL_DIR/venv/bin/python3"

            $py_bin -c "
import sys
try:
    from nbt import nbt
except ImportError:
    print('  -> Warning: nbt library missing. Skipping Data.Player injection.')
    sys.exit(0)

try:
    player_nbt = nbt.NBTFile('$latest_player', 'rb')
    level_nbt = nbt.NBTFile('$level_dat', 'rb')
    
    if 'Data' not in level_nbt:
        sys.exit(1)
        
    data_tag = level_nbt['Data']
    if 'Player' not in data_tag:
        data_tag.tags.append(nbt.TAG_Compound(name='Player'))
        
    player_tag = data_tag['Player']
    
    # Các thông số sinh tồn cốt lõi cần đồng bộ
    sync_tags = ['Inventory', 'Pos', 'Rotation', 'XpLevel', 'XpP', 'XpSeed', 'XpTotal', 'Health', 'foodLevel', 'foodTickTimer', 'foodExhaustionLevel', 'foodSaturationLevel', 'abilities']
    
    for t in sync_tags:
        if t in player_nbt:
            if t in player_tag:
                del player_tag[t]
            player_tag.tags.append(player_nbt[t])
            
    level_nbt.write_file('$level_dat')
    print('  -> NBT Injection successful. Character data synchronized.')
except Exception as e:
    print(f'  -> NBT Injection failed: {e}')
"
        fi
    fi
    # --- KẾT THÚC NBT TRANSFORMER HOOK ---

    echo "Compressing '$target' to $archive..."
    tar -czf "$archive" -C "$staging_dir" "$target"
    
    if [ -n "$SUDO_USER" ]; then chown "$SUDO_USER":"$SUDO_USER" "$archive"; fi
    
    # Dọn dẹp phân vùng tạm
    rm -rf "$staging_dir"
    
    local sz=$(du -sh "$archive" | cut -f1)
    echo "✅ Export complete! Archive saved at: $archive (Size: $sz)"
}

action_import() {
    read -p $'\nEnter absolute path to the map archive (.tar.gz): ' archive_path
    eval archive_path="$archive_path"
    archive_path="${archive_path%\"}"
    archive_path="${archive_path#\"}"
    
    if [ ! -f "$archive_path" ]; then echo "❌ File not found at $archive_path"; return; fi

    read -p "Enter new map name for this import: " newname
    if [[ ! "$newname" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "❌ Invalid name format."; return; fi
    if [ -d "$INSTALL_DIR/$newname" ]; then echo "❌ Map '$newname' already exists."; return; fi

    echo "Extracting map data..."
    local tmpdir=$(mktemp -d)
    tar -xzf "$archive_path" -C "$tmpdir"
    
    local extracted_world=$(find "$tmpdir" -name "level.dat" -printf '%h\n' -quit)
    if [ -z "$extracted_world" ]; then
        echo "❌ Invalid archive: No level.dat found inside the tarball."
        rm -rf "$tmpdir"
        return
    fi

    mv "$extracted_world" "$INSTALL_DIR/$newname"
    rm -rf "$tmpdir"

    local meta="$INSTALL_DIR/$newname/.minenux-meta.json"
    if [ ! -f "$meta" ]; then
        echo "⚠️ No Minenux metadata found in archive. Synthesizing config..."
        jq -n --arg seed "pending" --arg gm "survival" --arg ch "false" --arg created "$(date -Iseconds)" \
            '{seed: $seed, gamemode: $gm, cheats: $ch, created_at: $created, gamerules: {}, gamerules_applied: false}' \
            > "$meta"
    fi
    
    chown -R "$MC_USER":"$MC_USER" "$INSTALL_DIR/$newname"
    echo "✅ Map successfully imported as '$newname'."
}

action_delete() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to DELETE: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then echo "Invalid selection."; return; fi
    if [ "$target" == "$(prop_get level-name)" ]; then
        echo "Cannot delete the currently selected map. Switch to another map first."
        return
    fi
    read -p "Type the map name again to confirm permanent deletion: " confirm
    if [ "$confirm" != "$target" ]; then echo "Confirmation mismatch, aborted."; return; fi
    rm -rf "${INSTALL_DIR:?}/${target:?}"
    echo "🗑️  Map '$target' deleted."
}

while true; do
    print_header
    show_map_list
    echo ""
    echo "1) Switch active map"
    echo "2) Create new map (seed + gamerules)"
    echo "3) Edit live settings (Gamemode/Cheats/Rules)"
    echo "4) Rename a map"
    echo "5) Export a map"
    echo "6) Import a map"
    echo "7) Delete a map"
    echo "8) Exit"
    read -p "Choose an option: " opt
    case $opt in
        1) action_switch ;;
        2) action_create ;;
        3) action_edit_gamerules ;;
        4) action_rename ;;
        5) action_export ;;
        6) action_import ;;
        7) action_delete ;;
        8) echo "Bye."; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done