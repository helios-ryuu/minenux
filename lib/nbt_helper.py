#!/usr/bin/env python3
import gzip
import struct
import sys
import os
import uuid
import hashlib
import json
import urllib.request
import zipfile
import tarfile
import shutil

# --- NBT Tag Definitions ---
TAG_END = 0
TAG_BYTE = 1
TAG_SHORT = 2
TAG_INT = 3
TAG_LONG = 4
TAG_FLOAT = 5
TAG_DOUBLE = 6
TAG_BYTE_ARRAY = 7
TAG_STRING = 8
TAG_LIST = 9
TAG_COMPOUND = 10
TAG_INT_ARRAY = 11
TAG_LONG_ARRAY = 12

class NBTTag:
    def __init__(self, tag_type, name, value):
        self.tag_type = tag_type
        self.name = name
        self.value = value

    def __repr__(self):
        return f"NBTTag(type={self.tag_type}, name={repr(self.name)}, value={repr(self.value)})"

def read_tag(stream, tag_type=None, has_name=True):
    if tag_type is None:
        type_byte = stream.read(1)
        if not type_byte:
            return None
        tag_type = type_byte[0]

    if tag_type == TAG_END:
        return NBTTag(TAG_END, None, None)

    name = None
    if has_name:
        name_len_bytes = stream.read(2)
        if len(name_len_bytes) < 2:
            return None
        name_len = struct.unpack(">H", name_len_bytes)[0]
        name = stream.read(name_len).decode("utf-8", errors="replace")

    if tag_type == TAG_BYTE:
        value = struct.unpack(">b", stream.read(1))[0]
    elif tag_type == TAG_SHORT:
        value = struct.unpack(">h", stream.read(2))[0]
    elif tag_type == TAG_INT:
        value = struct.unpack(">i", stream.read(4))[0]
    elif tag_type == TAG_LONG:
        value = struct.unpack(">q", stream.read(8))[0]
    elif tag_type == TAG_FLOAT:
        value = struct.unpack(">f", stream.read(4))[0]
    elif tag_type == TAG_DOUBLE:
        value = struct.unpack(">d", stream.read(8))[0]
    elif tag_type == TAG_BYTE_ARRAY:
        length = struct.unpack(">i", stream.read(4))[0]
        value = bytearray(stream.read(length))
    elif tag_type == TAG_STRING:
        length = struct.unpack(">H", stream.read(2))[0]
        value = stream.read(length).decode("utf-8", errors="replace")
    elif tag_type == TAG_LIST:
        elem_type = stream.read(1)[0]
        length = struct.unpack(">i", stream.read(4))[0]
        elements = [read_tag(stream, elem_type, has_name=False) for _ in range(length)]
        value = (elem_type, elements)
    elif tag_type == TAG_COMPOUND:
        value = []
        while True:
            child = read_tag(stream, has_name=True)
            if child is None or child.tag_type == TAG_END:
                break
            value.append(child)
    elif tag_type == TAG_INT_ARRAY:
        length = struct.unpack(">i", stream.read(4))[0]
        value = list(struct.unpack(f">{length}i", stream.read(length * 4)))
    elif tag_type == TAG_LONG_ARRAY:
        length = struct.unpack(">i", stream.read(4))[0]
        value = list(struct.unpack(f">{length}q", stream.read(length * 8)))
    else:
        raise ValueError(f"Unknown NBT tag type: {tag_type}")

    return NBTTag(tag_type, name, value)

def write_tag(stream, tag, has_name=True):
    if tag.tag_type == TAG_END:
        stream.write(b"\x00")
        return

    if has_name:
        stream.write(struct.pack(">B", tag.tag_type))
        name_bytes = tag.name.encode("utf-8", errors="replace")
        stream.write(struct.pack(">H", len(name_bytes)))
        stream.write(name_bytes)

    if tag.tag_type == TAG_BYTE:
        stream.write(struct.pack(">b", tag.value))
    elif tag.tag_type == TAG_SHORT:
        stream.write(struct.pack(">h", tag.value))
    elif tag.tag_type == TAG_INT:
        stream.write(struct.pack(">i", tag.value))
    elif tag.tag_type == TAG_LONG:
        stream.write(struct.pack(">q", tag.value))
    elif tag.tag_type == TAG_FLOAT:
        stream.write(struct.pack(">f", tag.value))
    elif tag.tag_type == TAG_DOUBLE:
        stream.write(struct.pack(">d", tag.value))
    elif tag.tag_type == TAG_BYTE_ARRAY:
        stream.write(struct.pack(">i", len(tag.value)))
        stream.write(bytes(tag.value))
    elif tag.tag_type == TAG_STRING:
        val_bytes = tag.value.encode("utf-8", errors="replace")
        stream.write(struct.pack(">H", len(val_bytes)))
        stream.write(val_bytes)
    elif tag.tag_type == TAG_LIST:
        elem_type, elements = tag.value
        stream.write(struct.pack(">B", elem_type))
        stream.write(struct.pack(">i", len(elements)))
        for elem in elements:
            write_tag(stream, elem, has_name=False)
    elif tag.tag_type == TAG_COMPOUND:
        for child in tag.value:
            write_tag(stream, child, has_name=True)
        stream.write(b"\x00")
    elif tag.tag_type == TAG_INT_ARRAY:
        stream.write(struct.pack(">i", len(tag.value)))
        stream.write(struct.pack(f">{len(tag.value)}i", *tag.value))
    elif tag.tag_type == TAG_LONG_ARRAY:
        stream.write(struct.pack(">i", len(tag.value)))
        stream.write(struct.pack(f">{len(tag.value)}q", *tag.value))

def load_nbt(path):
    with gzip.open(path, "rb") as f:
        return read_tag(f)

def save_nbt(path, tag):
    with gzip.open(path, "wb") as f:
        write_tag(f, tag)

def find_child(compound_tag, name):
    if compound_tag.tag_type != TAG_COMPOUND:
        return None
    for child in compound_tag.value:
        if child.name == name:
            return child
    return None

def remove_child(compound_tag, name):
    if compound_tag.tag_type != TAG_COMPOUND:
        return False
    for i, child in enumerate(compound_tag.value):
        if child.name == name:
            compound_tag.value.pop(i)
            return True
    return False

# --- Core Player Data Operations ---

def get_offline_uuid(username):
    # Deterministic offline UUID: md5("OfflinePlayer:" + username) as UUID v3
    data = f"OfflinePlayer:{username}"
    hash_md5 = hashlib.md5(data.encode('utf-8')).digest()
    return str(uuid.UUID(bytes=hash_md5, version=3))

def get_player_uuid(username, online_mode=False):
    if online_mode:
        try:
            url = f"https://api.mojang.com/users/profiles/minecraft/{username}"
            req = urllib.request.Request(
                url, 
                headers={'User-Agent': 'Minenux-Helper'}
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    raw_uuid = data.get("id")
                    if raw_uuid:
                        # Format to standard 8-4-4-4-12 UUID format
                        formatted_uuid = str(uuid.UUID(raw_uuid))
                        print(f"  -> Resolved online UUID for '{username}': {formatted_uuid}")
                        return formatted_uuid
        except Exception as e:
            print(f"  -> Online UUID lookup failed: {e}. Falling back to offline UUID.")
    
    offline_uuid = get_offline_uuid(username)
    print(f"  -> Generated offline UUID for '{username}': {offline_uuid}")
    return offline_uuid

def inject_playerdata_to_level(player_dat_path, level_dat_path, gamemode="survival", cheats_enabled=False):
    player_root = load_nbt(player_dat_path)
    level_root = load_nbt(level_dat_path)

    # Find "Data" compound
    data_tag = find_child(level_root, "Data")
    if not data_tag:
        if level_root.name == "Data":
            data_tag = level_root
        else:
            raise ValueError("Could not find 'Data' tag in level.dat")

    # Replace "Player" in Data
    remove_child(data_tag, "Player")
    new_player_tag = NBTTag(TAG_COMPOUND, "Player", player_root.value)
    data_tag.value.append(new_player_tag)

    # Set GameType in Data
    gamemode_map = {"survival": 0, "creative": 1, "adventure": 2, "spectator": 3}
    gamemode_val = gamemode_map.get(gamemode.lower(), 0)
    
    gametype_tag = find_child(data_tag, "GameType")
    if gametype_tag:
        gametype_tag.value = gamemode_val
    else:
        data_tag.value.append(NBTTag(TAG_INT, "GameType", gamemode_val))

    # Set playerGameType in Player compound
    player_gametype_tag = find_child(new_player_tag, "playerGameType")
    if player_gametype_tag:
        player_gametype_tag.value = gamemode_val
    else:
        new_player_tag.value.append(NBTTag(TAG_INT, "playerGameType", gamemode_val))

    # Set allowCommands in Data
    allow_commands_val = 1 if cheats_enabled else 0
    allow_cmd_tag = find_child(data_tag, "allowCommands")
    if allow_cmd_tag:
        allow_cmd_tag.value = allow_commands_val
    else:
        data_tag.value.append(NBTTag(TAG_BYTE, "allowCommands", allow_commands_val))

    save_nbt(level_dat_path, level_root)
    print("  -> Successfully synchronized character data and level settings.")

def extract_playerdata_from_level(level_dat_path, player_dat_path):
    level_root = load_nbt(level_dat_path)
    data_tag = find_child(level_root, "Data")
    if not data_tag:
        if level_root.name == "Data":
            data_tag = level_root
        else:
            raise ValueError("Could not find 'Data' tag in level.dat")

    player_tag = find_child(data_tag, "Player")
    if not player_tag:
        print("  -> Warning: No 'Player' compound tag found in level.dat. Skipping sync.")
        return False

    # Standard playerdata files have a root compound named ""
    player_root = NBTTag(TAG_COMPOUND, "", player_tag.value)
    
    os.makedirs(os.path.dirname(player_dat_path), exist_ok=True)
    save_nbt(player_dat_path, player_root)
    print(f"  -> Successfully extracted singleplayer character data to: {player_dat_path}")
    return True

# --- Archive Processing Operations ---

def perform_export(map_dir, output_zip_path, gamemode="survival", cheats_enabled=False):
    # 1. Staging directory setup
    staging_dir = map_dir + "_export_staging"
    if os.path.exists(staging_dir):
        shutil.rmtree(staging_dir)
    
    shutil.copytree(map_dir, staging_dir)
    
    try:
        # 2. Ghost Player Mismatch Resolution
        player_dir = os.path.join(staging_dir, "playerdata")
        level_dat = os.path.join(staging_dir, "level.dat")
        
        if os.path.isdir(player_dir) and os.path.isfile(level_dat):
            dat_files = [
                os.path.join(player_dir, f) for f in os.listdir(player_dir) 
                if f.endswith(".dat") and os.path.isfile(os.path.join(player_dir, f))
            ]
            if dat_files:
                # Find most recently modified player data file
                latest_player = max(dat_files, key=os.path.getmtime)
                print(f"Syncing character data from '{os.path.basename(latest_player)}' into level.dat...")
                inject_playerdata_to_level(latest_player, level_dat, gamemode, cheats_enabled)
            else:
                print("No UUID playerdata files found. Exporting map as-is.")
        else:
            print("No playerdata folder or level.dat found. Exporting map as-is.")

        # 3. Create zip file
        parent_dir = os.path.dirname(staging_dir)
        map_dirname = os.path.basename(map_dir)
        os.makedirs(os.path.dirname(output_zip_path), exist_ok=True)
        
        print(f"Compressing world to: {output_zip_path}...")
        with zipfile.ZipFile(output_zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(staging_dir):
                for file in files:
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, parent_dir)
                    # Replace staging name with actual world name
                    rel_path = rel_path.replace(os.path.basename(staging_dir), map_dirname)
                    zipf.write(full_path, rel_path)
        
        print("Export completed successfully.")
    finally:
        if os.path.exists(staging_dir):
            shutil.rmtree(staging_dir)

def perform_import(archive_path, target_map_dir, username=None, online_mode=False):
    # 1. Staging extract area
    extract_temp = target_map_dir + "_import_temp"
    if os.path.exists(extract_temp):
        shutil.rmtree(extract_temp)
    os.makedirs(extract_temp)

    try:
        print(f"Extracting archive '{archive_path}'...")
        if archive_path.endswith(".tar.gz") or archive_path.endswith(".tgz"):
            with tarfile.open(archive_path, "r:gz") as tar:
                tar.extractall(path=extract_temp)
        else:
            # Default to zip
            with zipfile.ZipFile(archive_path, 'r') as zip_ref:
                zip_ref.extractall(extract_temp)

        # 2. Locate level.dat
        level_dat_found = None
        for root, dirs, files in os.walk(extract_temp):
            if "level.dat" in files:
                level_dat_found = os.path.join(root, "level.dat")
                break

        if not level_dat_found:
            raise FileNotFoundError("Invalid map archive: level.dat was not found.")

        source_world_dir = os.path.dirname(level_dat_found)

        # 3. Clean target map directory and copy extracted world
        if os.path.exists(target_map_dir):
            shutil.rmtree(target_map_dir)
        
        shutil.copytree(source_world_dir, target_map_dir)
        print(f"Extracted world folder moved to: {target_map_dir}")

        # 4. Resolve Singleplayer -> Dedicated Server Player Data Mismatch
        if username:
            print(f"Resolving player data for username '{username}'...")
            resolved_uuid = get_player_uuid(username, online_mode)
            level_dat = os.path.join(target_map_dir, "level.dat")
            player_dat = os.path.join(target_map_dir, "playerdata", f"{resolved_uuid}.dat")
            extract_playerdata_from_level(level_dat, player_dat)
    finally:
        if os.path.exists(extract_temp):
            shutil.rmtree(extract_temp)

# --- CLI Dispatcher ---

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: nbt_helper.py <command> [args...]")
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd == "export":
        if len(sys.argv) < 4:
            print("Usage: nbt_helper.py export <map_dir> <output_zip_path> [gamemode] [cheats]")
            sys.exit(1)
        map_dir = sys.argv[2]
        output_zip = sys.argv[3]
        gamemode = sys.argv[4] if len(sys.argv) > 4 else "survival"
        cheats = sys.argv[5].lower() == "true" if len(sys.argv) > 5 else False
        perform_export(map_dir, output_zip, gamemode, cheats)
    
    elif cmd == "import":
        if len(sys.argv) < 4:
            print("Usage: nbt_helper.py import <archive_path> <target_map_dir> [username] [online_mode]")
            sys.exit(1)
        archive_path = sys.argv[2]
        target_map_dir = sys.argv[3]
        username = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4].strip() != "" else None
        online_mode = sys.argv[5].lower() == "true" if len(sys.argv) > 5 else False
        perform_import(archive_path, target_map_dir, username, online_mode)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
