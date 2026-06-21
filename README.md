# Minenux: Ubuntu Minecraft Server Setup

This repository contains automated scripts to deploy an optimized Minecraft Fabric server on Ubuntu Linux. It adheres to system engineering standards: utilizing optimal Java Generational ZGC, avoiding headless classloading issues, automating via `systemd`, and exposing a local-only RCON interface for safe live administration (graceful saves, map switching, gamerule edits) without ever opening an extra port.

Additionally, Minenux features built-in solutions to resolve the **Ghost Player Mismatch** issue, synchronizing inventory, location, gamemode, and cheats settings between Singleplayer (Windows/Linux) and the Dedicated Server on export and import.

## Requirements
- Ubuntu 26.04 or later.
- Root privileges (`sudo`) to run the setup script.
- `python3` (installed automatically by `setup.sh` if missing).

## Directory Structure

```
minenux/
├── menu.sh              # Unified interactive dashboard console
├── setup.sh             # Interactive or unattended installer
├── up.sh                # Start the server (systemd) + show connection IP
├── down.sh              # Gracefully save and stop the server
├── map.sh               # Map manager: switch / create / edit / rename / delete / import / export
├── ip.sh                # Prints Tailscale / LAN connection address
├── give-exec.sh         # Grants execution permissions to all .sh files
├── uninstall.sh         # Full teardown
├── config.example.json  # Template for unattended installs
└── lib/
    ├── common.sh         # Shared functions (server.properties I/O, RCON, gamerules)
    ├── nbt_helper.py     # Pure Python NBT editor, UUID resolver, and cross-platform archiver
    └── rcon.py           # Minimal Source RCON client (stdlib only, no dependencies)
```

## Usage

First, grant execution permissions to the scripts using the provided helper:

```bash
chmod +x give-exec.sh
./give-exec.sh
```

### Method 1: Minenux Control Dashboard (Recommended)
Launch the interactive dashboard to manage all functions (setup, start, stop, restart, connection info, maps, uninstall) from a single screen:

```bash
./menu.sh
```
*(Note: The menu automatically invokes `sudo` for administrative actions as needed).*

### Method 2: Interactive CLI Setup
Run the setup script directly and follow the prompts. You'll be asked for the initial map's **name**, **seed** (random or custom), and a curated set of **gamerules** (`keepInventory`, `doDaylightCycle`, `doMobSpawning`, `mobGriefing`, `doFireTick`, `announceAdvancements`).

```bash
sudo ./setup.sh
```

### Method 3: Unattended Configuration Mode
You can automate the deployment by providing a JSON configuration file. Use the included `config.example.json` as a base.

```bash
cp config.example.json config.json
# Edit config.json with your preferences
sudo ./setup.sh --config config.json
```

The `initial_map` block controls the first world:

```json
"initial_map": {
  "name": "world",
  "seed_mode": "random",
  "seed": "",
  "gamerules": { "keepInventory": "false", "doDaylightCycle": "true", "...": "..." }
}
```

Set `"seed_mode": "custom"` and fill `"seed"` to pin a specific world seed instead of a random one.

*Note: The script will print a summary of all settings and ask for final confirmation. To skip the confirmation prompt and accept everything automatically, add the `-y` flag: `sudo ./setup.sh -y` or `sudo ./setup.sh --config config.json -y`.*

### Manual Mod Installation
If you have a downloaded `.jar` mod file (e.g., from CurseForge or Modrinth) and want to upload it to the server:

1. Upload the `.jar` file to your server (using SFTP/SCP via tools like FileZilla or WinSCP).
2. Move the file to the server's `mods` folder:
   ```bash
   sudo cp path/to/your/mod.jar /opt/minecraft/server/mods/
   ```
3. Fix the file permissions so the `minenux` user can read it:
   ```bash
   sudo chown minenux:minenux /opt/minecraft/server/mods/mod.jar
   sudo chmod 644 /opt/minecraft/server/mods/mod.jar
   ```
4. Restart the server:
   ```bash
   sudo ./down.sh
   sudo ./up.sh
   ```
*⚠️ CRITICAL WARNING: Never upload Client-Only mods (like Sodium, Iris, Xaero's Minimap) to the server. Your server will crash immediately due to "Headless" environment exceptions.*

## Server Management
Once installed, the server acts as a persistent background daemon, with RCON enabled on `127.0.0.1` only (never exposed externally) for safe automation:

- **Start Server (`up.sh`)**: Turns on the server, prints your Tailscale / LAN connection address, and auto-applies any gamerules that haven't been applied yet.
  ```bash
  sudo ./up.sh
  ```
- **Stop Server (`down.sh`)**: Sends `save-all` + `stop` over RCON before falling back to `systemctl stop`, so the world is always flushed to disk cleanly.
  ```bash
  sudo ./down.sh
  ```

Alternatively, you can manage it natively using systemctl:
- **View Live Logs**: `sudo journalctl -u minecraft -f`
- **Stop**: `sudo systemctl stop minecraft`
- **Restart**: `sudo systemctl restart minecraft`

## Map Management (`map.sh`)
A single install can hold multiple maps (worlds), stored as sibling folders under the install directory. Run:

```bash
sudo ./map.sh
```

This opens an interactive menu showing every map's status (`🟢 ACTIVE (running)`, `🟡 SELECTED (stopped)`, `⚪ INACTIVE`), disk size, and seed, with options to:

1. **Switch active map** — gracefully stops the current map, sets `level-name`, restarts.
2. **Create new map** — prompts for name, seed (random/custom), and gamerules; generates the world on first boot and applies the gamerules automatically once RCON comes online.
3. **Edit live settings (Gamemode/Cheats/Rules)** — queries current values live via RCON, lets you change them on the fly, and persists the new values. If cheats or gamemode is modified, currently connected players are immediately updated (OP status & active gamemode), and you'll be prompted to gracefully restart the server to apply non-RCON configurations.
4. **Rename a map** — blocked while that map is the active, running one.
5. **Export a map** — exports the world to a `.zip` archive (compatible with Windows & Linux singleplayer). It automatically retrieves the character data of the latest active player and injects it directly into the `level.dat`'s `Player` tag to prevent "Ghost Player Mismatch".
6. **Import a map** — imports a `.zip` or `.tar.gz` world. Supports importing from singleplayer: you can optionally provide your Minecraft username to extract the singleplayer `Player` data from `level.dat` and map it to your server character file (`playerdata/<UUID>.dat`) based on your online or offline UUID.
7. **Delete a map** — requires typing the map name again to confirm permanent deletion; blocked for the currently selected map.

Each map carries a hidden `.minenux-meta.json` (seed, creation date, gamerules, and an applied-flag) alongside its world data.

## Security Notes
- RCON is bound to `127.0.0.1` and only ever called by these scripts — it is never opened in UFW and should never be exposed to the network.
- The RCON password is auto-generated (`openssl rand -hex 16`) during setup; `server.properties` is `chmod 640`, owned by the dedicated service user.
- Combine this with the recommended **zero-exposed-port** architecture: keep `online-mode` and UFW rules scoped to your Tailscale interface where possible, and only open `25565/tcp` publicly if you specifically intend to run a public server.

## Uninstallation
To completely remove the server, delete all world data, and remove the `minenux` user, run:

```bash
sudo ./uninstall.sh
```
