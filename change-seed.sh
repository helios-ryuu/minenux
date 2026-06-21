#!/usr/bin/env bash

# Need root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

INSTALL_DIR="/opt/minecraft/server"

echo "=== CẢNH BÁO / WARNING ==="
echo "Thay đổi seed yêu cầu phải xoá (hoặc đổi tên) thư mục world hiện tại để server tạo map mới với seed mới."
echo "Thế giới hiện tại của bạn sẽ được sao lưu (backup) tự động, nhưng bạn đang thay đổi sang một map mới."
echo ""
read -p "Bạn có chắc chắn muốn đổi seed và tạo map mới? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Đã huỷ bỏ (Aborted)."
    exit 0
fi

read -p "Nhập Seed mới (để trống nếu muốn map ngẫu nhiên): " NEW_SEED

echo "Đang dừng server Minecraft (Stopping Minecraft server)..."
systemctl stop minecraft

# Backup the old world
WORLD_DIR="$INSTALL_DIR/world"
if [ -d "$WORLD_DIR" ]; then
    BACKUP_NAME="world_backup_$(date +%Y%m%d_%H%M%S)"
    echo "Đang sao lưu thế giới hiện tại thành $BACKUP_NAME..."
    mv "$WORLD_DIR" "$INSTALL_DIR/$BACKUP_NAME"
fi

if [ -f "$INSTALL_DIR/server.properties" ]; then
    # Modify seed in properties
    sed -i "s/^level-seed=.*/level-seed=$NEW_SEED/" "$INSTALL_DIR/server.properties"
    echo "Đã cập nhật seed trong server.properties."
else
    echo "Không tìm thấy server.properties trong $INSTALL_DIR!"
    exit 1
fi

echo "Đang khởi động lại server để tạo map mới..."
systemctl start minecraft

echo "Xong! Server đang chạy và sẽ tạo map mới với seed: $NEW_SEED"
echo "Kiểm tra log bằng lệnh: sudo journalctl -u minecraft -f"
