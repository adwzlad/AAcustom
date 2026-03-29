#!/bin/bash
set -e

# -------------------------------
# 删除 /dev/sda3 swap 分区 + 扩展根分区（保留 swapfile）
# -------------------------------

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 安装 parted 如果缺失
if ! command -v parted &>/dev/null; then
    echo "检测到 parted 未安装，正在安装..."
    apt update -y
    apt install -y parted
fi

# 检查 /dev/sda3 是否存在
if ! lsblk /dev/sda3 &>/dev/null; then
    echo "/dev/sda3 不存在，退出。"
    exit 1
fi

echo "关闭 /dev/sda3 swap..."
swapoff /dev/sda3

# 获取 /dev/sda3 的 UUID
uuid_sda3=$(blkid -s UUID -o value /dev/sda3 || true)

echo "删除 /dev/sda3 分区..."
parted /dev/sda --script rm 3

echo "扩展 /dev/sda2 到剩余空间..."
parted /dev/sda --script resizepart 2 100%

echo "重新加载分区表..."
partprobe /dev/sda

# 自动检测根分区文件系统类型
root_dev=$(findmnt -n -o SOURCE /)
fs_type=$(blkid -s TYPE -o value "$root_dev")

echo "检测到根分区 $root_dev 类型为 $fs_type"

if [ "$fs_type" = "ext4" ]; then
    echo "扩展 ext4 文件系统..."
    resize2fs "$root_dev"
elif [ "$fs_type" = "xfs" ]; then
    echo "扩展 xfs 文件系统..."
    xfs_growfs /
else
    echo "未支持的文件系统类型: $fs_type"
    echo "请手动扩展根分区"
fi

# 删除 fstab 中 /dev/sda3 对应 swap 条目
if [ -n "$uuid_sda3" ]; then
    echo "删除 fstab 中 /dev/sda3 (UUID=$uuid_sda3) 的 swap 条目..."
    sed -i "/$uuid_sda3/d" /etc/fstab
else
    echo "未检测到 /dev/sda3 UUID，尝试按设备名删除 fstab 中 swap 条目..."
    sed -i "/\/dev\/sda3/d" /etc/fstab
fi

echo "操作完成！保留其他 swapfile。请重启系统以生效。"
