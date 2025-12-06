#!/bin/bash
# ==========================================
# 全自动安装与配置 nftables（Debian/Ubuntu/Oracle Linux）
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

echo "=== Step 3: 写入 /etc/nftables.conf ==="
cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
# ==========================================
# Filter 表 - 放行 TCP/UDP/ICMP
# ==========================================
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        # 已建立连接允许
        ct state established,related accept
        # 回环接口允许
        iif lo accept
        # ICMP / ICMPv6 放行
        meta l4proto icmp accept
        meta l4proto ipv6-icmp accept
        # TCP 端口放行
        tcp dport {53,80,443,2053,2083,36098} accept
        # UDP 端口放行
        udp dport {53,443,63447,63448} accept
        udp dport 50000-60000 accept
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

echo "✅ 完成！请确认控制台放行对应端口，否则外网无法访问。"
