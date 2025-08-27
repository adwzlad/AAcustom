#!/bin/bash
set -e

# 安装依赖 jq
if ! command -v jq >/dev/null 2>&1; then
    echo "[INFO] 安装 jq..."
    sudo apt update
    sudo apt install -y jq
fi

SCRIPT="/usr/local/bin/oci_ipv6_sync.sh"

# 写入自动同步脚本
cat << 'EOF' > $SCRIPT
#!/bin/bash
set -e

# 获取默认网卡
iface=$(ip route | awk '/^default/ {print $5; exit}')
[[ -z "$iface" ]] && { echo "[ERROR] 未找到默认网卡"; exit 1; }

# 获取 OCI 分配的所有 IPv6 地址
ipv6_list=($(curl -s http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].ipv6Addresses[].ipAddress'))
[[ ${#ipv6_list[@]} -eq 0 ]] && { echo "[ERROR] OCI 未返回 IPv6"; exit 1; }

# 获取默认 IPv6 网关
gw=$(ip -6 route | awk '/default/ {print $3; exit}')
[[ -z "$gw" ]] && gw="fe80::1"

# 清理旧 IPv6
ip -6 addr flush dev "$iface" scope global

# 绑定所有 IPv6
for ip in "${ipv6_list[@]}"; do
    ip -6 addr add "$ip/64" dev "$iface"
done

# 设置默认路由
ip -6 route add default via "$gw" dev "$iface" || true

# 输出绑定结果
echo "[INFO] 已绑定 IPv6: ${ipv6_list[*]}"
EOF

chmod +x $SCRIPT

# 创建 systemd 服务
cat << EOF > /etc/systemd/system/oci_ipv6_sync.service
[Unit]
Description=OCI IPv6 Sync Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT
EOF

# 创建 systemd 定时器（每 10 分钟同步一次）
cat << EOF > /etc/systemd/system/oci_ipv6_sync.timer
[Unit]
Description=Run OCI IPv6 Sync every 10 minutes

[Timer]
OnBootSec=30s
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启用并立即启动定时器
systemctl enable --now oci_ipv6_sync.timer

# 立即执行一次，确保开机 IPv6 生效
$SCRIPT

echo "✅ IPv6 自动同步完成（完全忽略 IPv4，jq 已自动安装）"
