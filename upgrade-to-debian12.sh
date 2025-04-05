#!/bin/bash

set -e

echo "📦 开始升级系统到 Debian 12 (bookworm)..."

# 1. 备份源文件
echo "📝 备份 /etc/apt/sources.list 为 sources.list.bak"
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 2. 替换 bullseye 为 bookworm
echo "🔄 更新 sources.list 中的版本代号..."
sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list

# 3. 更新包索引
echo "🔄 执行 apt update..."
apt update

# 4. 升级当前系统（重要）
echo "⬆️ 执行 apt upgrade..."
apt upgrade -y

# 5. 执行完整系统升级
echo "⬆️ 执行 apt full-upgrade..."
apt full-upgrade -y

# 6. 自动清理不再需要的包
echo "🧹 清理旧包..."
apt autoremove -y

echo "✅ 升级完成，请重启系统以应用更改！"
echo "💡 重启命令：sudo reboot"
