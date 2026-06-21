# Minenux: Ubuntu Minecraft Server Setup

This repository contains automated scripts to deploy an optimized Minecraft Fabric server on Ubuntu Linux. It adheres to system engineering standards: utilizing optimal Java Generational ZGC, avoiding headless classloading issues, and automating via `systemd`.

## Requirements
- Ubuntu 26.04 or later.
- Root privileges (`sudo`) to run the setup script.

## Usage

### Method 1: Interactive Mode
Run the setup script without any arguments and follow the prompts.

```bash
sudo ./setup.sh
```

### Method 2: Unattended Configuration Mode
You can automate the entire deployment by providing a JSON configuration file. Use the included `config.example.json` as a base.

```bash
cp config.example.json config.json
# Edit config.json with your preferences
sudo ./setup.sh --config config.json
```

### Mod Downloader
To download server-side compatible mods directly from Modrinth, use the `mods_downloader.sh` script.

```bash
sudo su - minenux
cd /opt/minecraft/server
/path/to/mods_downloader.sh "P7dR8mSH" "gvQqBUqZ" "9s6osm5g"
```
*Note: The arguments above are the Modrinth Project IDs for Fabric API, Lithium, and Cloth Config.*

## Server Management
Once installed, the server acts as a persistent background daemon:
- **View Live Logs**: `sudo journalctl -u minecraft -f`
- **Stop Server**: `sudo systemctl stop minecraft`
- **Start/Restart**: `sudo systemctl restart minecraft`
