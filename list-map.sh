#!/usr/bin/env bash
# list-map.sh - interactive map manager.
# Deliberately NOT using `set -e`: this is a long-lived interactive menu where
# individual commands (grep/jq with no match, an invalid menu choice, etc.)
# are expected to fail without aborting the whole script.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

require_root

print_header() {
    echo ""
    echo "============================================================"
    echo " Minenux Map Manager  -  $INSTALL_DIR"
    echo "============================================================"
}

# Populates the global MAPS array (intentionally not `local`: every action_*
# function below calls show_map_list first and then reads MAPS by index).
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
    if [ -z "$target" ]; then
        echo "Invalid selection."
        return
    fi

    local current
    current=$(prop_get level-name)
    if [ "$target" == "$current" ]; then
        echo "'$target' is already the selected map."
        return
    fi

    echo "Switching active map: $current -> $target"
    graceful_stop
    prop_set level-name "$target"
    echo "Starting server with map '$target'..."
    systemctl start minecraft
    apply_pending_gamerules "$target"
    echo "✅ Server is now running map '$target'."
}

action_create() {
    read -p $'\nNew map name (letters, numbers, dash, underscore): ' name
    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Invalid name."
        return
    fi
    if [ -d "$INSTALL_DIR/$name" ]; then
        echo "A map named '$name' already exists."
        return
    fi

    local seed rules
    seed=$(prompt_seed)
    rules=$(prompt_gamerules)

    graceful_stop
    mkdir -p "$INSTALL_DIR/$name"
    chown -R "$MC_USER":"$MC_USER" "$INSTALL_DIR/$name"

    jq -n --arg seed "$seed" --argjson rules "$rules" --arg created "$(date -Iseconds)" \
        '{seed: $seed, created_at: $created, gamerules: $rules, gamerules_applied: false}' \
        > "$INSTALL_DIR/$name/.minenux-meta.json"
    chown "$MC_USER":"$MC_USER" "$INSTALL_DIR/$name/.minenux-meta.json"

    prop_set level-name "$name"
    prop_set level-seed "$seed"

    echo "Starting server to generate the new world (first boot can take 1-3 min)..."
    systemctl start minecraft
    apply_pending_gamerules "$name"
    echo "✅ Map '$name' created and active (seed: ${seed:-random})."
}

action_edit_gamerules() {
    local current meta json
    current=$(prop_get level-name)
    if ! is_server_running; then
        echo "Server must be running to edit live gamerules. Switch to / start a map first."
        return
    fi

    echo "Editing gamerules for active map '$current' (Enter to keep current value)."
    meta="$INSTALL_DIR/$current/.minenux-meta.json"
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
        tmp=$(jq --argjson rules "$json" '.gamerules = $rules' "$meta")
        echo "$tmp" > "$meta"
        chown "$MC_USER":"$MC_USER" "$meta" 2>/dev/null
    fi
    echo "✅ Gamerules updated live, and saved so they persist next time this map loads."
}

action_rename() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to rename: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then
        echo "Invalid selection."
        return
    fi
    if [ "$target" == "$(prop_get level-name)" ] && is_server_running; then
        echo "Stop the server (or switch off this map) before renaming it."
        return
    fi
    read -p "New name for '$target': " newname
    if [[ ! "$newname" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Invalid name."
        return
    fi
    if [ -d "$INSTALL_DIR/$newname" ]; then
        echo "Name already in use."
        return
    fi

    mv "$INSTALL_DIR/$target" "$INSTALL_DIR/$newname"
    if [ "$target" == "$(prop_get level-name)" ]; then
        prop_set level-name "$newname"
    fi
    echo "✅ Renamed '$target' to '$newname'."
}

action_delete() {
    show_map_list
    [ ${#MAPS[@]} -eq 0 ] && return
    read -p $'\nSelect map number to DELETE: ' idx
    local target="${MAPS[$((idx - 1))]}"
    if [ -z "$target" ]; then
        echo "Invalid selection."
        return
    fi
    if [ "$target" == "$(prop_get level-name)" ]; then
        echo "Cannot delete the currently selected map. Switch to another map first."
        return
    fi
    read -p "Type the map name again to confirm permanent deletion: " confirm
    if [ "$confirm" != "$target" ]; then
        echo "Confirmation mismatch, aborted."
        return
    fi
    rm -rf "${INSTALL_DIR:?}/${target:?}"
    echo "🗑️  Map '$target' deleted."
}

while true; do
    print_header
    show_map_list
    echo ""
    echo "1) Switch active map"
    echo "2) Create new map (seed + gamerules)"
    echo "3) Edit gamerules of the running map"
    echo "4) Rename a map"
    echo "5) Delete a map"
    echo "6) Exit"
    read -p "Choose an option: " opt
    case $opt in
        1) action_switch ;;
        2) action_create ;;
        3) action_edit_gamerules ;;
        4) action_rename ;;
        5) action_delete ;;
        6) echo "Bye."; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
