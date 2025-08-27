#!/bin/bash
# full_backup.sh
# 高效整盘备份（仅有效数据）+ 自动生成 manifest + SHA256 + 压缩
# 用法: sudo ./full_backup.sh /dev/sdX /path/to/backup_dir [pigz|zstd]

set -euo pipefail

DISK="$1"
DEST_DIR="$2"
COMPRESS_TOOL="${3:-pigz}"   # 默认 pigz

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 身份运行"
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "用法: $0 <磁盘> <目标目录> [压缩工具 pigz|zstd]"
  exit 1
fi

mkdir -p "$DEST_DIR"
LOG="$DEST_DIR/backup.log"
echo "=== 备份开始 $(date) ===" | tee -a "$LOG"

# 保存分区表
echo "[+] 保存分区表..." | tee -a "$LOG"
sfdisk -d "$DISK" > "$DEST_DIR/disk_layout.sfdisk"
sgdisk --backup="$DEST_DIR/disk_layout.gpt" "$DISK" || true

# 自动生成 manifest.csv
lsblk -ln -o NAME,FSTYPE "$DISK" | grep part | awk '{print $1","$2}' > "$DEST_DIR/manifest.csv"
echo "[+] 生成 manifest.csv" | tee -a "$LOG"

# 遍历分区
lsblk -ln -o NAME,TYPE,FSTYPE "$DISK" | grep part | while read -r PART TYPE FS; do
  DEV="/dev/$PART"
  [[ -z "$FS" ]] && { echo "[-] $DEV 没有文件系统，跳过" | tee -a "$LOG"; continue; }

  OUT="$DEST_DIR/${PART}.img"
  echo "[+] 备份 $DEV ($FS) -> $OUT" | tee -a "$LOG"

  case "$FS" in
    ext4) CMD="partclone.ext4" ;;
    ext3) CMD="partclone.ext3" ;;
    ext2) CMD="partclone.ext2" ;;
    xfs)  CMD="partclone.xfs" ;;
    ntfs) CMD="partclone.ntfs" ;;
    fat|vfat) CMD="partclone.fat" ;;
    btrfs) CMD="partclone.btrfs" ;;
    swap) echo "[-] $DEV 是 swap，跳过" | tee -a "$LOG"; continue ;;
    *) echo "[-] 不支持的文件系统: $FS，跳过" | tee -a "$LOG"; continue ;;
  esac

  SIZE=$(blockdev --getsize64 "$DEV")

  if [[ "$COMPRESS_TOOL" == "pigz" ]]; then
    $CMD -c -s "$DEV" -o - \
      | pv -s "$SIZE" \
      | tee >(sha256sum > "${OUT}.sha256") \
      | pigz -p $(nproc) -c > "${OUT}.gz"
  else
    $CMD -c -s "$DEV" -o - \
      | pv -s "$SIZE" \
      | tee >(sha256sum > "${OUT}.sha256") \
      | zstd -T$(nproc) -19 -o "${OUT}.zst"
  fi

  echo "[+] 完成: $DEV" | tee -a "$LOG"
done

echo "=== 备份完成 $(date) ===" | tee -a "$LOG"
