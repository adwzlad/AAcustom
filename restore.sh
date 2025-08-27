#!/bin/bash
# full_restore.sh
# 一键恢复脚本：自动写分区表 + 按 manifest 恢复 + 校验 SHA256
# 用法: sudo ./full_restore.sh /dev/sdX /path/to/backup_dir

set -euo pipefail

TARGET_DISK="$1"
BACKUP_DIR="$2"
LOG="$BACKUP_DIR/restore.log"

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 运行."
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "用法: $0 /dev/sdX /path/to/backup_dir"
  exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "备份目录不存在: $BACKUP_DIR"
  exit 1
fi

echo "=== 恢复开始 $(date) ===" | tee -a "$LOG"
echo "目标磁盘: $TARGET_DISK" | tee -a "$LOG"
echo "备份目录: $BACKUP_DIR" | tee -a "$LOG"

read -p "警告：该操作会覆盖 $TARGET_DISK 上的数据。输入磁盘设备名称（例如 $(basename $TARGET_DISK)）以确认: " CONF
if [[ "$CONF" != "$(basename $TARGET_DISK)" ]]; then
  echo "确认失败，退出。" | tee -a "$LOG"
  exit 1
fi

# 写分区表
if [[ -f "$BACKUP_DIR/disk_layout.sfdisk" ]]; then
  echo "[+] 写入 sfdisk 分区表 ..." | tee -a "$LOG"
  sfdisk "$TARGET_DISK" < "$BACKUP_DIR/disk_layout.sfdisk"
elif [[ -f "$BACKUP_DIR/disk_layout.gpt" ]]; then
  echo "[+] 写入 GPT 分区表 ..." | tee -a "$LOG"
  sgdisk --load-backup="$BACKUP_DIR/disk_layout.gpt" "$TARGET_DISK"
else
  echo "找不到分区表备份。" | tee -a "$LOG"
  exit 1
fi

partprobe "$TARGET_DISK" || true
sleep 2

# manifest
MANIFEST="$BACKUP_DIR/manifest.csv"
if [[ ! -f "$MANIFEST" ]]; then
  echo "找不到 manifest.csv，无法恢复" | tee -a "$LOG"
  exit 1
fi

fs_to_tool() {
  case "$1" in
    ext4) echo "partclone.ext4" ;;
    ext3) echo "partclone.ext3" ;;
    ext2) echo "partclone.ext2" ;;
    xfs)  echo "partclone.xfs" ;;
    ntfs) echo "partclone.ntfs" ;;
    fat|vfat) echo "partclone.fat" ;;
    btrfs) echo "partclone.btrfs" ;;
    swap) echo "" ;;
    *) echo "" ;;
  esac
}

while IFS=, read -r PART FS || [[ -n "$PART" ]]; do
  PART="${PART//[[:space:]]/}"
  FS="${FS//[[:space:]]/}"
  [[ -z "$PART" ]] && continue

  PARTNUM=$(echo "$PART" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')
  TARGET_PART="/dev/$(basename $TARGET_DISK)${PARTNUM}"

  echo "[+] 准备恢复 -> $TARGET_PART (fs: $FS)" | tee -a "$LOG"

  BASE="$BACKUP_DIR/${PART}.img"
  GZ_FILE="${BASE}.gz"
  ZST_FILE="${BASE}.zst"
  RAW_SHA="${BASE}.sha256"

  if [[ -f "$GZ_FILE" ]]; then COMPRESS="gz"; IMG_FILE="$GZ_FILE"
  elif [[ -f "$ZST_FILE" ]]; then COMPRESS="zst"; IMG_FILE="$ZST_FILE"
  else echo "找不到镜像文件: $BASE"; exit 1; fi

  [[ ! -f "$RAW_SHA" ]] && { echo "缺少 sha 文件: $RAW_SHA"; exit 1; }

  echo "[+] 校验 $IMG_FILE ..." | tee -a "$LOG"
  if [[ "$COMPRESS" == "gz" ]]; then
    pigz -dc "$IMG_FILE" | sha256sum -c --status "$RAW_SHA"
  else
    zstd -dc "$IMG_FILE" | sha256sum -c --status "$RAW_SHA"
  fi
  echo "[+] 校验通过" | tee -a "$LOG"

  TOOL=$(fs_to_tool "$FS")
  [[ -z "$TOOL" ]] && { echo "跳过 fs: $FS"; continue; }
  command -v "$TOOL" >/dev/null 2>&1 || { echo "缺少工具: $TOOL"; exit 1; }

  echo "[+] 恢复 $TARGET_PART ..." | tee -a "$LOG"
  if [[ "$COMPRESS" == "gz" ]]; then
    pigz -dc "$IMG_FILE" | $TOOL -r -s - -o "$TARGET_PART" --force
  else
    zstd -dc "$IMG_FILE" | $TOOL -r -s - -o "$TARGET_PART" --force
  fi

  echo "[+] 完成: $TARGET_PART" | tee -a "$LOG"
done < "$MANIFEST"

partprobe "$TARGET_DISK" || true
echo "=== 恢复完成 $(date) ===" | tee -a "$LOG"
