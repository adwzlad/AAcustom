#!/bin/bash
set -e

echo "=== Step 1: 停止 nftables 服务 ==="
systemctl stop nftables
systemctl disable nftables

echo "=== Step 2: 删除 /etc/nftables.conf ==="
if [ -f /etc/nftables.conf ]; then
    rm -f /etc/nftables.conf
    echo "/etc/nftables.conf 已删除"
fi

echo "=== Step 3: 卸载 nftables 软件包 ==="
if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    apt remove --purge -y nftables
elif [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    dnf remove -y nftables
fi

echo "=== Step 4: 清空内存中已加载的规则 ==="
nft flush ruleset

echo "✅ nftables 已完全撤销，系统恢复原状态。"
