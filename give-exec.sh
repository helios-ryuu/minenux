#!/usr/bin/env bash
# give-exec.sh - grant execution permissions to all Minenux scripts.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Granting execution permissions to all Minenux scripts in $DIR..."
chmod +x "$DIR"/*.sh
echo "✅ Permissions updated."
