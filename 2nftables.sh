#!/bin/bash
set +e  # 允许错误，不会中断脚本

echo "=== Step 1: 停止 nftables 服务 ==="
systemctl stop nftables || echo "⚠️ 停止服务失败，可能未安装或未启用"
systemctl disable nftables || echo "⚠️ 禁用服务失败，可能未启用"

echo "=== Step 2: 删除 /etc/nftables.conf ==="
if [ -f /etc/nftables.conf ]; then
    rm -f /etc/nftables.conf || echo "⚠️ 删除 /etc/nftables.conf 失败"
    echo "/etc/nftables.conf 已删除"
else
    echo "/etc/nftables.conf 不存在，跳过"
fi

echo "=== Step 3: 卸载 nftables 软件包 ==="
if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    apt remove --purge -y nftables || echo "⚠️ 卸载 nftables 失败或未安装"
elif [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    dnf remove -y nftables || echo "⚠️ 卸载 nftables 失败或未安装"
else
    echo "❌ 未识别的系统，跳过卸载"
fi

echo "=== Step 4: 清空内存中已加载的规则 ==="
nft flush ruleset || echo "⚠️ 清空规则失败"

echo "✅ nftables 已尝试完全撤销，系统恢复原状态（如未报错）"
