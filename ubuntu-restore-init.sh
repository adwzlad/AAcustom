#!/bin/bash
set -e

echo "================================="
echo " OCI ARM 救砖恢复初始化"
echo "================================="

# 输入新的主机名
read -p "请输入新的主机名: " NEW_NAME

if [ -z "$NEW_NAME" ]; then
    echo "主机名不能为空"
    exit 1
fi


echo
echo "[1/6] 修改主机名: $NEW_NAME"

hostnamectl set-hostname "$NEW_NAME"

sed -i "s/\bjarm\b/$NEW_NAME/g" /etc/hosts


echo
echo "[2/6] 重新生成 machine-id"

truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
systemd-machine-id-setup


echo
echo "[3/6] 重新生成 SSH Host Key"

rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

systemctl restart ssh


echo
echo "[4/6] 清理 cloud-init 状态"

if command -v cloud-init >/dev/null 2>&1; then
    cloud-init clean --logs
fi


echo
echo "[5/6] 检查磁盘扩容"

# 安装 growpart 工具
if ! command -v growpart >/dev/null 2>&1; then
    apt update
    apt install -y cloud-guest-utils
fi


DISK_SIZE=$(lsblk -b -dn -o SIZE /dev/sda)
PART_SIZE=$(lsblk -b -dn -o SIZE /dev/sda2)

if [ "$DISK_SIZE" -gt "$PART_SIZE" ]; then

    echo "检测到磁盘空间增加，开始扩容..."

    growpart /dev/sda 2

    resize2fs /dev/sda2

    echo "扩容完成"

else

    echo "未检测到额外空间，跳过扩容"

fi


echo
echo "[6/6] 保存修改"

sync


echo
echo "================================="
echo "恢复初始化完成"
echo "新主机名: $NEW_NAME"
echo "系统将在 10 秒后重启"
echo "================================="

sleep 10

reboot
