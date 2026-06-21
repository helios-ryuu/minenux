#!/usr/bin/env python3
import os
import sys
import tempfile
import shutil
import unittest

# Add lib directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "lib"))
from nbt_helper import (
    NBTTag, TAG_BYTE, TAG_INT, TAG_COMPOUND, TAG_STRING,
    load_nbt, save_nbt, find_child, remove_child,
    get_offline_uuid, inject_playerdata_to_level, extract_playerdata_from_level
)

class TestNBTAndHelper(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        
    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_basic_nbt_read_write(self):
        # Create a simple nested NBT structure
        data = NBTTag(TAG_COMPOUND, "Root", [
            NBTTag(TAG_INT, "NumberVal", 42),
            NBTTag(TAG_STRING, "StringVal", "Hello NBT"),
            NBTTag(TAG_COMPOUND, "SubCompound", [
                NBTTag(TAG_BYTE, "ByteVal", 1)
            ])
        ])
        
        filepath = os.path.join(self.test_dir, "test.dat")
        save_nbt(filepath, data)
        
        # Reload
        loaded = load_nbt(filepath)
        
        self.assertEqual(loaded.tag_type, TAG_COMPOUND)
        self.assertEqual(loaded.name, "Root")
        
        num_tag = find_child(loaded, "NumberVal")
        self.assertIsNotNone(num_tag)
        self.assertEqual(num_tag.value, 42)
        
        str_tag = find_child(loaded, "StringVal")
        self.assertIsNotNone(str_tag)
        self.assertEqual(str_tag.value, "Hello NBT")
        
        sub_tag = find_child(loaded, "SubCompound")
        self.assertIsNotNone(sub_tag)
        byte_tag = find_child(sub_tag, "ByteVal")
        self.assertIsNotNone(byte_tag)
        self.assertEqual(byte_tag.value, 1)

    def test_offline_uuid_generation(self):
        # Username: "Helios"
        # Offline UUID for "Helios" is 479a3acd-34bb-3b8d-9be8-34ff75e869e9
        uuid_helios = get_offline_uuid("Helios")
        self.assertEqual(uuid_helios, "479a3acd-34bb-3b8d-9be8-34ff75e869e9")

    def test_injection_and_extraction(self):
        # 1. Setup dummy level.dat NBT structure
        level_dat_structure = NBTTag(TAG_COMPOUND, "", [
            NBTTag(TAG_COMPOUND, "Data", [
                NBTTag(TAG_INT, "GameType", 0),
                NBTTag(TAG_BYTE, "allowCommands", 0),
                NBTTag(TAG_COMPOUND, "Player", [
                    NBTTag(TAG_STRING, "OldAttribute", "OldValue")
                ])
            ])
        ])
        level_path = os.path.join(self.test_dir, "level.dat")
        save_nbt(level_path, level_dat_structure)

        # 2. Setup dummy playerdata NBT structure
        player_dat_structure = NBTTag(TAG_COMPOUND, "", [
            NBTTag(TAG_STRING, "NewAttribute", "NewValue"),
            NBTTag(TAG_INT, "Health", 20)
        ])
        player_path = os.path.join(self.test_dir, "player.dat")
        save_nbt(player_path, player_dat_structure)

        # 3. Test Injection: playerdata.dat -> level.dat
        inject_playerdata_to_level(player_path, level_path, gamemode="creative", cheats_enabled=True)

        # 4. Verify level.dat updates
        updated_level = load_nbt(level_path)
        data_tag = find_child(updated_level, "Data")
        self.assertIsNotNone(data_tag)
        
        # Verify allowCommands is now 1 (cheats_enabled=True)
        allow_cmds = find_child(data_tag, "allowCommands")
        self.assertEqual(allow_cmds.value, 1)
        
        # Verify GameType is now 1 (creative)
        gametype = find_child(data_tag, "GameType")
        self.assertEqual(gametype.value, 1)

        # Verify Player tag is updated
        player_tag = find_child(data_tag, "Player")
        self.assertIsNotNone(player_tag)
        self.assertIsNone(find_child(player_tag, "OldAttribute")) # Should be deleted
        new_attr = find_child(player_tag, "NewAttribute")
        self.assertIsNotNone(new_attr)
        self.assertEqual(new_attr.value, "NewValue")

        # 5. Test Extraction: level.dat -> new_playerdata.dat
        new_player_path = os.path.join(self.test_dir, "new_player.dat")
        extract_playerdata_from_level(level_path, new_player_path)

        # 6. Verify extracted playerdata
        extracted_player = load_nbt(new_player_path)
        self.assertEqual(extracted_player.tag_type, TAG_COMPOUND)
        self.assertEqual(extracted_player.name, "")
        
        new_attr_ext = find_child(extracted_player, "NewAttribute")
        self.assertIsNotNone(new_attr_ext)
        self.assertEqual(new_attr_ext.value, "NewValue")

if __name__ == "__main__":
    unittest.main()
