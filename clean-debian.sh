#!/bin/bash
# Debian 12 一键清理垃圾脚本
# 作者: ChatGPT

set -e

echo "=== 🚀 开始清理 Debian 系统垃圾文件 ==="

# 1. APT 缓存清理
echo "[1/5] 清理 APT 缓存..."
sudo apt clean
sudo apt autoclean -y
sudo apt autoremove -y

# 2. 清理日志文件（保留 7 天，限制总大小 100M）
echo "[2/5] 清理系统日志..."
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=100M

# 3. 清理临时文件
echo "[3/5] 清理临时文件..."
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# 4. 清理旧内核
echo "[4/5] 检查旧内核..."
CURRENT_KERNEL=$(uname -r)
OLD_KERNELS=$(dpkg --list | grep linux-image | awk '{print $2}' | grep -v $CURRENT_KERNEL || true)

if [ -n "$OLD_KERNELS" ]; then
    echo "发现旧内核，开始清理..."
    sudo apt remove --purge -y $OLD_KERNELS
    sudo apt autoremove -y
else
    echo "未发现旧内核，无需清理。"
fi

# 5. Docker 清理（可选）
if command -v docker &> /dev/null; then
    echo "[5/5] 清理 Docker 无用资源..."
    sudo docker system prune -a -f --volumes
else
    echo "[5/5] 未检测到 Docker，跳过。"
fi

echo "=== ✅ 清理完成！磁盘空间已释放 ==="

# 显示剩余空间
df -h /
