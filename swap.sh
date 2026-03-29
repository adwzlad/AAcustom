#!/bin/bash
set -e

# ⚠️ 危险操作，务必备份！

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 检查 /dev/sda3 是否存在
if ! lsblk /dev/sda3 &>/dev/null; then
    echo "/dev/sda3 不存在，退出。"
    exit 1
fi

echo "关闭 swap..."
swapoff -a

# 获取 /dev/sda3 的 UUID（如果有）
uuid_sda3=$(blkid -s UUID -o value /dev/sda3 || true)

echo "删除 /dev/sda3 分区..."
parted /dev/sda --script rm 3

echo "扩展 /dev/sda2 到剩余空间..."
parted /dev/sda --script resizepart 2 100%

echo "重新加载分区表..."
partprobe /dev/sda

echo "扩展文件系统..."
# 假设根分区是 ext4
resize2fs /dev/sda2

# 通用删除 fstab 中对应 swap 条目
if [ -n "$uuid_sda3" ]; then
    echo "删除 fstab 中 /dev/sda3 (UUID=$uuid_sda3) 的 swap 条目..."
    sed -i "/$uuid_sda3/d" /etc/fstab
else
    echo "未检测到 /dev/sda3 UUID，尝试按设备名删除 fstab 中 swap 条目..."
    sed -i "/\/dev\/sda3/d" /etc/fstab
fi

echo "操作完成，请重启系统以生效。"
