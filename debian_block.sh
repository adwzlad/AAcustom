#!/bin/bash
set -e

# ==================== 权限检查 ====================
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行"
    exit 1
fi

# ==================== 依赖安装 ====================
install_deps() {
    echo "检查并安装依赖..."
    DEPS=(partclone sfdisk gzip e2fsprogs xfsprogs btrfs-progs ntfs-3g sha256sum pv)
    apt update -y
    for pkg in "${DEPS[@]}"; do
        dpkg -l | grep -qw "$pkg" || {
            echo "安装 $pkg ..."
            DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
        }
    done
}

# ==================== 磁盘与分区 ====================
list_disks() {
    echo "可用磁盘列表:"
    lsblk -dn -o NAME,SIZE,MODEL | awk '{print NR": /dev/"$1" "$2" "$3}'
}

get_partclone_tool() {
    case "$1" in
        ext2|ext3|ext4) echo "partclone.extfs" ;;
        xfs) echo "partclone.xfs" ;;
        btrfs) echo "partclone.btrfs" ;;
        ntfs) echo "partclone.ntfs" ;;
        vfat|fat16|fat32) echo "partclone.fat" ;;
        *) echo "partclone.dd" ;;
    esac
}

confirm() {
    read -rp "⚠️ $1 (yes/NO): " yn
    [[ "$yn" != "yes" ]] && echo "已取消" && exit 1
}

# ==================== 备份 ====================
backup() {
    echo "==== 备份 ===="
    list_disks
    read -rp "输入磁盘 (如 /dev/sdb): " DISK
    read -rp "输入备份目录: " DEST_DIR
    read -rp "输入备份文件名（无需后缀）: " FILENAME

    DEST="$DEST_DIR/$FILENAME.img.gz"
    SHA_FILE="$DEST_DIR/$FILENAME.sha256"
    mkdir -p "$DEST_DIR"
    confirm "备份 $DISK -> $DEST"

    echo "=== 备份分区表 ==="
    sfdisk -d "$DISK" | gzip | tee >(sha256sum > "$SHA_FILE") | pv -n > "$DEST"

    mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE "$DISK" | awk '$2=="part"{print "/dev/"$1}')
    for part in "${PARTS[@]}"; do
        fs=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "raw")
        SIZE=$(blockdev --getsize64 "$part")
        echo "备份 $part ($fs), 大小 $(($SIZE/1024/1024)) MB"

        echo "---partclone $(basename $part)---" | gzip | tee -a >(sha256sum >> "$SHA_FILE") >> "$DEST"

        get_partclone_tool "$fs" -c -s "$part" -o - | pv -s "$SIZE" | gzip | tee -a >(sha256sum >> "$SHA_FILE") >> "$DEST"
    done
    echo "✅ 备份完成: $DEST"
    echo "SHA256 文件: $SHA_FILE"
}

# ==================== 恢复 ====================
restore() {
    echo "==== 恢复 ===="
    read -rp "输入备份文件路径: " SRC
    read -rp "输入恢复目标磁盘 (如 /dev/sdb): " DEST_DISK
    SHA_FILE="${SRC%.gz}.sha256"
    confirm "恢复 $DEST_DISK <- $SRC"

    if [ -f "$SHA_FILE" ]; then
        echo "验证备份文件 SHA256..."
        sha256sum -c "$SHA_FILE" || { echo "校验失败，停止恢复"; exit 1; }
    fi

    if ! sfdisk -d "$DEST_DISK" &>/dev/null; then
        echo "⚠️ 目标盘分区表无效，自动清空"
        dd if=/dev/zero of="$DEST_DISK" bs=1M count=10
    fi

    echo "=== 恢复分区表 ==="
    gzip -dc "$SRC" | sed '/^---partclone /q' | sfdisk "$DEST_DISK"
    partprobe "$DEST_DISK"
    sleep 1

    mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE "$DEST_DISK" | awk '$2=="part"{print "/dev/"$1}')
    for part in "${PARTS[@]}"; do
        fs=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "raw")
        SIZE=$(blockdev --getsize64 "$part")
        echo "恢复 $part ($fs), 大小 $(($SIZE/1024/1024)) MB"

        gzip -dc "$SRC" | awk "/^---partclone $(basename $part)---/{flag=1;next}/^---partclone /{flag=0}flag" \
            | pv -s "$SIZE" \
            | get_partclone_tool "$fs" -r -s /dev/stdin -o "$part"

        case "$fs" in
            ext2|ext3|ext4) resize2fs "$part" ;;
            xfs) xfs_growfs "$part" ;;
            btrfs) btrfs filesystem resize max "$part" ;;
            ntfs) ntfsresize --size max "$part" ;;
        esac
    done
    echo "✅ 全盘恢复完成"
}

# ==================== 主菜单 ====================
install_deps

while true; do
    echo "======================"
    echo "1) 备份磁盘"
    echo "2) 恢复磁盘"
    echo "0) 退出"
    echo "======================"
    read -rp "选择: " opt
    case "$opt" in
        1) backup ;;
        2) restore ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done
