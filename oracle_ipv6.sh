#!/bin/bash
# 自动生成 IPv6 配置脚本，并添加定时任务和开机启动
# 作者: ChatGPT

# === 检查 IPv6 文件是否存在 ===
IPV6_FILE="/root/oracle_ipv6"
if [[ ! -f "$IPV6_FILE" ]]; then
    echo "[错误] 未找到 $IPV6_FILE 文件"
    exit 1
fi

IPV6_ADDR=$(cat $IPV6_FILE | head -n 1 | tr -d '[:space:]')
if [[ -z "$IPV6_ADDR" ]]; then
    echo "[错误] IPv6 地址为空，请检查 $IPV6_FILE"
    exit 1
fi

# === 检测网卡名称 ===
if ip link show ens3 >/dev/null 2>&1; then
    NIC="ens3"
elif ip link show enp0s6 >/dev/null 2>&1; then
    NIC="enp0s6"
else
    echo "[错误] 未找到 ens3 或 enp0s6 网卡"
    exit 1
fi

echo "[信息] 检测到网卡: $NIC"
echo "[信息] 使用 IPv6 地址: $IPV6_ADDR"

# === 生成执行脚本 ===
AUTO_SCRIPT="/usr/local/bin/auto_ipv6.sh"
cat > $AUTO_SCRIPT <<EOF
#!/bin/bash
# 自动添加 Oracle Cloud IPv6 地址
IPV6_ADDR="$IPV6_ADDR"
NIC="$NIC"

# 检查 IPv6 是否已存在
if ! ip -6 addr show dev \$NIC | grep -q "\$IPV6_ADDR"; then
    echo "[\$(date)] IPv6 地址缺失，正在添加..."
    ip -6 addr add \$IPV6_ADDR/128 dev \$NIC
    # 确保默认路由存在
    if ! ip -6 route show | grep -q "default via"; then
        GATEWAY="\$(echo \$IPV6_ADDR | sed 's/::[0-9a-fA-F]*\$/::1/')"
        ip -6 route add default via \$GATEWAY dev \$NIC
    fi
else
    echo "[\$(date)] IPv6 地址已存在，无需处理"
fi
EOF

chmod +x $AUTO_SCRIPT
echo "[信息] 已生成 $AUTO_SCRIPT"

# === 添加开机启动 ===
SERVICE_FILE="/etc/systemd/system/auto-ipv6.service"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Auto IPv6 Configuration for Oracle Cloud
After=network.target

[Service]
Type=oneshot
ExecStart=$AUTO_SCRIPT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable auto-ipv6.service

echo "[信息] 已创建 systemd 服务：auto-ipv6.service"

# === 添加 5 分钟定时检查 ===
CRON_CMD="*/5 * * * * $AUTO_SCRIPT >> /var/log/auto_ipv6.log 2>&1"
(crontab -l 2>/dev/null | grep -v "$AUTO_SCRIPT"; echo "$CRON_CMD") | crontab -

echo "[信息] 已添加 cron 任务，每 5 分钟检查一次 IPv6"

echo "[完成] 现在执行：sudo systemctl start auto-ipv6.service"
