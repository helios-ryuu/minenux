#!/usr/bin/env bash

# This script downloads Universal / Server-Side mods using the Modrinth API.
# It resolves the correct physical URL via jq.
# Usage: ./mods_downloader.sh <project_id1> <project_id2> ...
# Example: ./mods_downloader.sh P7dR8mSH gvQqBUqZ 9s6osm5g

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <project_id_1> [project_id_2] ..."
    echo "Example: $0 P7dR8mSH gvQqBUqZ 9s6osm5g"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' not found. Please install jq (e.g., sudo apt install jq)."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' not found."
    exit 1
fi

TARGET_GAME_VERSION="26.2"

echo "Minenux Automod: Starting Modrinth API Fetcher for Game Version $TARGET_GAME_VERSION"
echo "--------------------------------------------------------"

for PROJECT_ID in "$@"; do
    echo "[*] Querying API for project ID: $PROJECT_ID..."
    
    # Query Modrinth for this project's versions, filter by matching target game version and loader=fabric
    # We grab the first (most recent) version uploaded that matches the criteria
    VERSIONS_JSON=$(curl -s "https://api.modrinth.com/v2/project/$PROJECT_ID/version")
    
    FILE_URL=$(echo "$VERSIONS_JSON" | jq -r --arg ver "$TARGET_GAME_VERSION" '
        [ .[] | select(.game_versions[] == $ver) | select(.loaders[] == "fabric") ] 
        | .[0].files[] | select(.primary == true) | .url 
    ')
    
    FILE_NAME=$(echo "$VERSIONS_JSON" | jq -r --arg ver "$TARGET_GAME_VERSION" '
        [ .[] | select(.game_versions[] == $ver) | select(.loaders[] == "fabric") ] 
        | .[0].files[] | select(.primary == true) | .filename 
    ')

    if [ -n "$FILE_URL" ] && [ "$FILE_URL" != "null" ]; then
        echo "[+] Found compatible version: $FILE_NAME"
        echo "[+] Downloading..."
        wget -q --show-progress -O "$FILE_NAME" "$FILE_URL"
        echo "[+] Downloaded $FILE_NAME successfully."
    else
        echo "[-] FAILED: No compatible stable release found for game version $TARGET_GAME_VERSION."
    fi
    echo "--------------------------------------------------------"
done

echo "Setting read permissions..."
chmod 644 *.jar

echo "Task completed. Do not forget to restart systemd service: sudo systemctl restart minecraft"
