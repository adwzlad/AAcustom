#!/bin/bash
# ==========================================
# nftables 一键配置脚本（默认全放行）
# UDP 50000-60000 → 63448
# ==========================================
set -e

echo "=== Step 1: 安装 nftables ==="
if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    apt update
    apt install -y nftables
elif [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    dnf install -y nftables
else
    echo "❌ 未识别的系统，请手动安装 nftables"
    exit 1
fi

echo "=== Step 2: 启用 nftables 服务 ==="
systemctl enable nftables
systemctl start nftables

echo "=== Step 3: 写入 /etc/nftables.conf（默认全放行） ==="
cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
# ==========================================
# Filter 表 - 默认全部放行（ACCEPT）
# ==========================================
table inet filter {
	chain input {
		type filter hook input priority filter; policy accept;
	}
	chain forward {
		type filter hook forward priority filter; policy accept;
	}
	chain output {
		type filter hook output priority filter; policy accept;
	}
}
# ==========================================
# NAT 表 - UDP 50000-60000 重定向到 63448
# ==========================================
table inet nat {
	chain prerouting {
		type nat hook prerouting priority dstnat; policy accept;
		udp dport 50000-60000 redirect to :63448
	}
}
EOF

echo "=== Step 4: 立即加载规则 ==="
nft -f /etc/nftables.conf

echo "=== Step 5: 查看规则 ==="
nft list ruleset

echo "✅ 完成！现在系统层面所有端口放行，但仍保留 UDP 端口重定向。"
echo "🔔 外网访问的放行控制请在控制台中设置。"
