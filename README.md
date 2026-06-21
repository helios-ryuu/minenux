# Minenux: Ubuntu Minecraft Server Setup

This repository contains automated scripts to deploy an optimized Minecraft Fabric server on Ubuntu Linux. It adheres to system engineering standards: utilizing optimal Java Generational ZGC, avoiding headless classloading issues, and automating via `systemd`.

## Requirements
- Ubuntu 26.04 or later.
- Root privileges (`sudo`) to run the setup script.

## Usage

First, grant execution permissions to the scripts:

```bash
chmod +x setup.sh mods_downloader.sh uninstall.sh server-up.sh server-down.sh
```

### Method 1: Interactive Mode
Run the setup script without any arguments and follow the prompts.

```bash
sudo ./setup.sh
```

### Method 2: Unattended Configuration Mode
You can automate the deployment by providing a JSON configuration file. Use the included `config.example.json` as a base.

```bash
cp config.example.json config.json
# Edit config.json with your preferences
sudo ./setup.sh --config config.json
```

*Note: The script will print a summary of all settings and ask for final confirmation. To skip the confirmation prompt and accept everything automatically, add the `-y` flag: `sudo ./setup.sh -y` or `sudo ./setup.sh --config config.json -y`.*

### Mod Downloader
To download server-side compatible mods directly from Modrinth, use the `mods_downloader.sh` script.

```bash
sudo su - minenux
cd /opt/minecraft/server
/path/to/mods_downloader.sh "P7dR8mSH" "gvQqBUqZ" "9s6osm5g"
```
*Note: The arguments above are the Modrinth Project IDs for Fabric API, Lithium, and Cloth Config.*

## Server Management
Once installed, the server acts as a persistent background daemon. We provide utility scripts to manage it easily:

- **Start Server (`server-up.sh`)**: Turns on the server and displays the Public IP address you should use to connect in-game.
  ```bash
  sudo ./server-up.sh
  ```
- **Stop Server (`server-down.sh`)**: Safely shuts down the server.
  ```bash
  sudo ./server-down.sh
  ```

Alternatively, you can manage it natively using systemctl:
- **View Live Logs**: `sudo journalctl -u minecraft -f`
- **Stop**: `sudo systemctl stop minecraft`
- **Restart**: `sudo systemctl restart minecraft`

## Uninstallation
To completely remove the server, delete all world data, and remove the `minenux` user, run:

```bash
sudo ./uninstall.sh
```
